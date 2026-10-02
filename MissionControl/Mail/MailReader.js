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

function resolveInbox(mail, account, accountID) {
    // Resolve an account's exact Inbox, rather than an aggregate child mailbox.
    // Resolve the specifier now. Leaving an indexed mailbox unevaluated makes
    // Mail repeat expensive account/mailbox resolution on every property read.
    const names = listValue(account.mailboxes.name());
    for (let i = 0; i < names.length; i += 1) {
        if (stringValue(names[i]).toLowerCase() === 'inbox') return account.mailboxes[i]();
    }
    throw new Error('Inbox mailbox not found for this account');
}

function runHeaders(mail, input) {
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
            if (input.accountID && String(input.accountID) !== accountID) return;
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
        const message = inbox.messages.byId(messageID)();
        if (!message) throw new Error('Inbox message not found');
        const unreadBefore = !Boolean(message.readStatus());
        const body = stringValue(message.content());
        const unreadAfter = !Boolean(message.readStatus());
        return {
            body: body,
            unreadBefore: unreadBefore,
            unreadAfter: unreadAfter,
            internetMessageID: stringValue(message.messageId()),
            errors: []
        };
    } catch (error) {
        return { body: '', internetMessageID: '', errors: [accountError(accountID, error)] };
    }
}

// Resolve one date window once, then paginate a persisted list of message IDs.
// Array.slice below is ordinary JavaScript; never use Mail's indexed range
// specifier, which can copy the whole inbox once for every selected index.
function runBatch(mail, input) {
    const accountID = String(input.accountID || '');
    const start = new Date(Number(input.start) * 1000);
    const end = new Date(Number(input.end) * 1000);
    const offset = Number(input.offset || 0);
    const limit = Math.min(20, Number(input.limit || 20));
    if (!accountID || !Number.isFinite(start.getTime()) || !(start < end) || !Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1) throw new Error('Invalid Mail batch');
    const account = mail.accounts.byId(accountID)();
    if (!account.enabled()) throw new Error('Mail account is unavailable');
    const inbox = resolveInbox(mail, account, accountID);
    let ids = input.messageIDs;
    if (!Array.isArray(ids)) {
        const refs = listValue(inbox.messages.whose({ _and: [
            { dateReceived: { _greaterThanEquals: start } }, { dateReceived: { _lessThan: end } }
        ] })());
        ids = refs.map(message => Number(message.id()));
    }
    if (ids.some(id => !Number.isSafeInteger(id) || id < 0)) throw new Error('Invalid message identity in batch');
    const title = stringValue(account.name());
    const page = ids.slice(offset, offset + limit);
    const messages = page.map(function (id) {
        const message = inbox.messages.byId(id)();
        const received = dateISO(message.dateReceived());
        if (!received || new Date(received) < start || new Date(received) >= end) throw new Error('A message changed or moved; retry this date window');
        return { id: accountID + ':' + id, accountID: accountID, account: title, messageID: id,
            internetMessageID: stringValue(message.messageId()), sender: stringValue(message.sender()),
            subject: stringValue(message.subject()), received: received, unread: !Boolean(message.readStatus()),
            replied: Boolean(message.wasRepliedTo()), flagged: Boolean(message.flaggedStatus()) };
    });
    return { messages: messages, messageIDs: ids, nextOffset: offset + page.length,
        complete: offset + page.length >= ids.length, errors: [] };
}

function probeInboxes(mail) {
    const accounts = [], errors = [];
    mail.accounts().forEach(function(account) {
        if (!account.enabled()) return;
        const id = stringValue(account.id());
        try { accounts.push({ id: id, title: stringValue(account.name()), inbox: stringValue(resolveInbox(mail, account, id).name()) }); }
        catch (error) { errors.push(accountError(id, error)); }
    });
    return { accounts: accounts, errors: errors };
}
function run(argv) {
    try {
        if (!argv || argv.length !== 1) {
            throw new Error('Expected exactly one JSON argument');
        }
        const input = JSON.parse(argv[0]);
        const mail = Application('Mail');
        let output;
        if (input.operation === 'batch') {
            output = runBatch(mail, input);
        } else if (input.operation === 'probe') {
            output = probeInboxes(mail);
        } else if (input.operation === 'headers') {
            output = runHeaders(mail, input);
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
