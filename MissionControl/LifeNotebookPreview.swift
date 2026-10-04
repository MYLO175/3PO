#if DEBUG
import SwiftUI
import AppKit

/// Fictional, local-only visual fixture. No subscription call or user-source refresh.
@MainActor enum LifeNotebookPreview {
    static func render() {
        var owner=PAMemory(registration:"fixture",text:"My name is Alex.",kind:.context,provenance:"Fictional preview",evidence:"My name is Alex.",certainty:.stated,durability:.stable,organisation:.init(areas:[.about],connections:[],selfName:"Alex"))
        owner.connections=[.init(subject:"You",relation:"name",object:"Alex",evidence:"My name is Alex.")]
        let areas:[LifeArea]=[.studies,.career,.projects,.interests,.wellbeing,.people,.home,.administration]
        var records=[owner]
        for area in areas {
            records.append(PAMemory(registration:"fixture",text:"Fictional note about " + area.title,kind:.context,provenance:"Visual fixture",organisation:.init(areas:[area],connections:[])))
        }
        records.append(PAMemory(registration:"fixture",text:"Signal Garden is a project developing practical engineering skills.",kind:.context,provenance:"Fictional preview",organisation:.init(areas:[.studies,.projects],connections:[])))
        let notebook=LifeNotebook.build(records,registration:"fixture")
        for (name,width,mode) in [("light",CGFloat(700),"light"),("dark",CGFloat(700),"dark"),("narrow",CGFloat(320),"dark")] {
            var overrides=WorkspaceColorOverrides();overrides.profiles=WorkspaceColorTheme.threePO.profiles
            let palette=WorkspacePalette.resolved(raw:overrides.encoded,mode:mode,theme:"warm",accent:"sage")
            let preview=VStack(alignment:.leading,spacing:16) {
                HStack { Label("Life map",systemImage:"point.3.connected.trianglepath.dotted").font(.title2.weight(.semibold));Spacer();Text("3PO").foregroundStyle(palette[.accent]) }
                LifeNotebookMapView(notebook:notebook,notes:notebook.notes,selectedArea:.constant(.projects))
                Text("Personal projects · linked areas share saved facts").font(.caption).foregroundStyle(palette[.accent])
            }.padding(24).frame(width:width).foregroundStyle(palette[.text]).background(palette[.widget],in:RoundedRectangle(cornerRadius:24)).padding(20).background(palette[.canvas]).environment(\.workspacePalette,palette).preferredColorScheme(mode == "dark" ? .dark : .light)
            let renderer=ImageRenderer(content:preview);renderer.scale=2
            renderer.proposedSize = .init(width:width+40,height:LifeMapLayout(width:width-48,count:notebook.notes.count).height+145)
            if let image=renderer.nsImage,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let data=bitmap.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-3po-map-"+name+".png"),options:.atomic) }
        }
    }
}
#endif
