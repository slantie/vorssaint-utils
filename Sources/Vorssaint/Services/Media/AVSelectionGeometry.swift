// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

struct AVRangeDrag {
    enum Mode { case create, start, end, move }
    let mode: Mode
    let original: ClosedRange<Double>
    let anchor: Double
    let duration: Double
    init(range: ClosedRange<Double>?,anchor: Double,duration: Double,tolerance: Double) {
        self.duration = duration; self.anchor = anchor
        self.original = range ?? anchor...anchor
        if let range {
            if abs(anchor-range.lowerBound) <= tolerance { mode = .start }
            else if abs(anchor-range.upperBound) <= tolerance { mode = .end }
            else { mode = .move }
        } else { mode = .create }
    }
    func range(at position: Double) -> ClosedRange<Double>? {
        guard duration.isFinite, duration > 0, anchor.isFinite, position.isFinite,
              original.lowerBound >= 0, original.upperBound <= duration else { return nil }
        let position = min(duration,max(0,position)), minimum = min(0.01,duration)
        switch mode {
        case .create:
            let low = min(position,anchor), high = max(position,anchor)
            return high-low >= minimum ? low...high : nil
        case .start: return min(max(0,position),max(0,original.upperBound-minimum))...original.upperBound
        case .end: return original.lowerBound...max(original.lowerBound+minimum,position)
        case .move:
            let length = original.upperBound-original.lowerBound
            let low = min(max(0,original.lowerBound+position-anchor),duration-length)
            return low...(low+length)
        }
    }
}
extension AVTimeInputs {
    static func step(_ time: Double,direction: Int,fps: Double,duration: Double) -> Double? {
        guard time.isFinite, fps.isFinite, duration.isFinite, fps > 0, duration > 0 else { return nil }
        return min(max(0,(round(time*fps)+Double(direction))/fps),max(0,duration-1/fps))
    }
}
