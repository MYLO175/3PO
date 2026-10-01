#!/usr/bin/osascript -l JavaScript
// Read Mail headers or a single message body. Input is one JSON argument;
// stdout is exactly one JSON object so Swift can decode it directly.

ObjC.import('Foundation');

function jsonOutput(value) {
    const data = $.NSJSONSerialization.dataWithJSONObjectOptionsError(
        value, $.NSJSONWritingFragmentsAllowed, null
    );
    if (!data) throw new Error('Could not encode JSON output');
    return ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
}

function stringValue(value) {
    if (value === null || value === undefined) return '';
    return String(ObjC.unwrap(value));
}

function listValue(value) {
    if (value === null || value === undefined) return [];
    return Array.isArray(value) ? value : [value];
}

function dateISO(value) {
    if (!value) return null;
    const seconds = value instanceof Date
        ? value.getTime() / 1000
        : Number(ObjC.unwrap(value).timeIntervalSince1970());
    if (!Number.isFinite(seconds)) return null;
    return new Date(seconds * 1000).toISOString();
}

function accountError(accountID, message) {
    const label = accountID ? 'Account ' + accountID : 'Mail';
    return label + ': ' + String(message);
}

function mailboxChildren(mailbox) {
    try {
        return listValue(mailbox.mailboxes());
    } catch (_) {
        return [];
    }
}

function accountIDForMailbox(mailbox) {
    try {
        return stringValue(mailbox.account().id());
    } catch (_) {
        return '';
    }
}

function findInboxInTree(mailbox, accountID, depth, requireAccountMatch) {
    if (depth > 8) return null;
    const children = mailboxChildren(mailbox);
    for (let i = 0; i < children.length; i += 1) {
        const child = children[i];
        const name = stringValue(child.name()).toLocaleLowerCase();
        if ((name === 'inbox') && (!requireAccountMatch || accountIDForMailbox(child) === accountID)) return child;
        const nested = findInboxInTree(child, accountID, depth + 1, requireAccountMatch);
        if (nested) return nested;
    }
    return null;
}

function resolveInbox(mail, account, accountID) {
    // Mail exposes an aggregate Inbox at the application level. Its child
    // mailboxes can be mapped back to the account that owns each inbox.
    try {
        const rootInbox = mail.inbox();
        const children = mailboxChildren(rootInbox);
        for (let i = 0; i < children.length; i += 1) {
            if (accountIDForMailbox(children[i]) === accountID) return children[i];
        }
    } catch (_) {
        // Fall through to the account's own mailbox tree.
    }

    const found = findInboxInTree(account, accountID, 0, false);
    if (found) return found;
    throw new Error('Inbox mailbox not found for this account');
}

function runHeaders(mail) {
    const accounts = [];
    const messages = [];
    const errors = [];
    const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    let sourceAccounts;

    try {
        sourceAccounts = mail.accounts();
    } catch (error) {
        return { messages: [], accounts: [], errors: [accountError(null, error)] };
    }

    sourceAccounts.forEach(function (account) {
        let accountID = null;
        let title = 'Mail account';
        try {
            if (!account.enabled()) return;
            accountID = stringValue(account.id());
            title = stringValue(account.name()) || title;
            const inbox = resolveInbox(mail, account, accountID);
            // Ask Mail to filter by date before fetching properties. Then each
            // property is requested for the whole result set in one Apple event.
            const recent = inbox.messages.whose({ dateReceived: { _greaterThan: cutoff } });
            const ids = listValue(recent.id());
            const internetIDs = listValue(recent.messageId());
            const senders = listValue(recent.sender());
            const subjects = listValue(recent.subject());
            const dates = listValue(recent.dateReceived());
            const unread = listValue(recent.readStatus());
            const replied = listValue(recent.wasRepliedTo());
            const flagged = listValue(recent.flaggedStatus());
            const count = ids.length;
            const accountMessages = [];

            for (let i = 0; i < count; i += 1) {
                const messageID = Number(ids[i]);
                const received = dateISO(dates[i]);
                if (!Number.isFinite(messageID) || !received) continue;
                accountMessages.push({
                    id: accountID + ':' + String(messageID),
                    accountID: accountID,
                    account: title,
                    messageID: messageID,
                    internetMessageID: stringValue(internetIDs[i]),
                    sender: stringValue(senders[i]),
                    subject: stringValue(subjects[i]),
                    received: received,
                    unread: !Boolean(unread[i]),
                    replied: Boolean(replied[i]),
                    flagged: Boolean(flagged[i])
                });
            }
            messages.push.apply(messages, accountMessages);
            accounts.push({ id: accountID, title: title });
        } catch (error) {
            errors.push(accountError(accountID, error));
        }
    });

    return { messages: messages, accounts: accounts, errors: errors };
}

function runBody(mail, input) {
    const accountID = String(input.accountID || '');
    const messageID = Number(input.messageID);
    if (!accountID || !Number.isSafeInteger(messageID) || messageID < 0) {
        return { body: '', internetMessageID: '', errors: [accountError(accountID, 'Invalid accountID or messageID')] };
    }

    try {
        const account = mail.accounts.byId(accountID);
        if (!account || !account.enabled()) throw new Error('Enabled Mail account not found');
        const inbox = resolveInbox(mail, account, accountID);
        const message = inbox.messages.byId(messageID);
        if (!message) throw new Error('Inbox message not found');
        // Reading the content property does not open the message or set its read status.
        return {
            body: stringValue(message.content()),
            internetMessageID: stringValue(message.messageId()),
            errors: []
        };
    } catch (error) {
        return { body: '', internetMessageID: '', errors: [accountError(accountID, error)] };
    }
}

function run(argv) {
    try {
        if (!argv || argv.length !== 1) {
            throw new Error('Expected exactly one JSON argument');
        }
        const input = JSON.parse(argv[0]);
        const mail = Application('Mail');
        let output;
        if (input.operation === 'headers') {
            output = runHeaders(mail);
        } else if (input.operation === 'body') {
            output = runBody(mail, input);
        } else {
            output = { messages: [], accounts: [], errors: [accountError(null, 'Unsupported operation')] };
        }
        return jsonOutput(output);
    } catch (error) {
        return jsonOutput({ messages: [], accounts: [], errors: [accountError(null, error)] });
    }
}
