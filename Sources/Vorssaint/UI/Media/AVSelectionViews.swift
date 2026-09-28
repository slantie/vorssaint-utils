// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import SwiftUI

struct AVWaveformSelection: View {
    let image: CGImage
    let duration: Double
    let regions: [AVTimedArea]
    let commit: (UUID?,ClosedRange<Double>) -> Void
    @State private var drag: AVRangeDrag?
    @State private var selected: UUID?
    @State private var draft: ClosedRange<Double>?
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment:.topLeading) {
                Image(decorative:image,scale:1).resizable().frame(width:geometry.size.width,height:geometry.size.height)
                ForEach(regions) { region in
                    let range = selected == region.id ? draft ?? region.start...region.end : region.start...region.end
                    rangeBox(range,width:geometry.size.width,height:geometry.size.height)
                }
                if selected == nil, let draft { rangeBox(draft,width:geometry.size.width,height:geometry.size.height) }
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:2).onChanged { value in
                guard duration > 0, geometry.size.width > 0 else { return }
                let scale = duration/geometry.size.width, anchor = min(duration,max(0,value.startLocation.x*scale))
                if drag == nil {
                    let region = regions.last { anchor >= $0.start-8*scale && anchor <= $0.end+8*scale }
                    selected = region?.id
                    drag = AVRangeDrag(range:region.map { $0.start...$0.end },anchor:anchor,duration:duration,tolerance:8*scale)
                }
                draft = drag?.range(at:value.location.x*scale)
            }.onEnded { _ in
                if let draft { commit(selected,draft) }
                draft = nil; drag = nil; selected = nil
            })
        }.frame(height:130).background(FileToolAppearance.card,in:RoundedRectangle(cornerRadius:12))
    }
    private func rangeBox(_ range: ClosedRange<Double>,width: CGFloat,height: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(FileToolAppearance.accent.opacity(0.2)).overlay(Rectangle().stroke(FileToolAppearance.accent,lineWidth:2))
            HStack { Capsule().fill(.white).frame(width:3,height:20); Spacer(); Capsule().fill(.white).frame(width:3,height:20) }.padding(.horizontal,3)
        }.frame(width:max(2,(range.upperBound-range.lowerBound)/duration*width),height:height).offset(x:range.lowerBound/duration*width).allowsHitTesting(false)
    }
}

struct AVImageSelection: View {
    let image: CGImage
    let crop: CGRect?
    let regions: [AVTimedArea]
    let commit: (UUID?,CGRect) -> Void
    @State private var draft: CGRect?
    @State private var moving: UUID?
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width/CGFloat(image.width),geometry.size.height/CGFloat(image.height))
            let size = CGSize(width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
            ZStack(alignment:.topLeading) {
                Image(decorative:image,scale:1).resizable().frame(width:size.width,height:size.height)
                if let crop { outline(draft ?? crop,size:size) }
                ForEach(regions) { region in outline(moving == region.id ? draft ?? region.rect : region.rect,size:size) }
                if crop == nil, moving == nil, let draft { outline(draft,size:size) }
            }.frame(width:size.width,height:size.height).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:2).onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                let start = CGPoint(x:value.startLocation.x/size.width,y:value.startLocation.y/size.height)
                if crop == nil, let region = regions.last(where:{ $0.rect.contains(start) }) {
                    moving = region.id
                    draft = CGRect(x:min(max(0,region.rect.minX+(value.location.x-value.startLocation.x)/size.width),1-region.rect.width),y:min(max(0,region.rect.minY+(value.location.y-value.startLocation.y)/size.height),1-region.rect.height),width:region.rect.width,height:region.rect.height)
                } else {
                    draft = try? ImageFileTools.normalized(CGRect(x:min(value.startLocation.x,value.location.x)/size.width,y:min(value.startLocation.y,value.location.y)/size.height,width:abs(value.location.x-value.startLocation.x)/size.width,height:abs(value.location.y-value.startLocation.y)/size.height))
                }
            }.onEnded { _ in if let draft { commit(moving,draft) }; draft = nil; moving = nil })
                .frame(width:geometry.size.width,height:geometry.size.height)
        }.frame(height:180).background(FileToolAppearance.card,in:RoundedRectangle(cornerRadius:12))
    }
    private func outline(_ rect: CGRect,size: CGSize) -> some View {
        Rectangle().fill(FileToolAppearance.accent.opacity(0.15)).overlay(Rectangle().stroke(FileToolAppearance.accent,lineWidth:2)).frame(width:max(1,rect.width*size.width),height:max(1,rect.height*size.height)).offset(x:rect.minX*size.width,y:rect.minY*size.height).allowsHitTesting(false)
    }
}
