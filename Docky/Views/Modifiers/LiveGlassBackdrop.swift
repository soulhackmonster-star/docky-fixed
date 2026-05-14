//
//  LiveGlassBackdrop.swift
//  Docky
//
//  Real-glass NSView backed by a private CABackdropLayer with CAFilter
//  composition (gaussianBlur + saturation). Unlike SwiftUI's `.glassEffect`,
//  CABackdropLayer auto-samples its backdrop at compositor time, so the
//  blur stays live as windows move behind the dock. Used as the chrome
//  material when materialStyle == .liquidGlass.
//
//  Both CABackdropLayer and CAFilter are private QuartzCore classes loaded
//  by name. Integration is fragile — class signatures or filter type
//  strings could change between macOS versions — but the visible behavior
//  is what we want and there is no public alternative that live-tracks.
//

import AppKit
import QuartzCore
import SwiftUI

struct LiveGlassBackdrop: NSViewRepresentable {
    var cornerRadius: CGFloat
    var blurRadius: Double = 25
    var saturation: Double = 1.8

    func makeNSView(context: Context) -> LiveGlassBackdropView {
        LiveGlassBackdropView()
    }

    func updateNSView(_ view: LiveGlassBackdropView, context: Context) {
        view.apply(cornerRadius: cornerRadius, blurRadius: blurRadius, saturation: saturation)
    }
}

final class LiveGlassBackdropView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        apply(cornerRadius: 0, blurRadius: 25, saturation: 1.8)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not available") }

    override func makeBackingLayer() -> CALayer {
        #if !APP_STORE_SANDBOX
        // `CABackdropLayer` is a private Core Animation class. The
        // literal name lives only inside this gate so the MAS binary
        // has no string reference to it (App Review's scanner flags
        // private class names regardless of whether they're called).
        if let cls = NSClassFromString("CABackdropLayer") as? CALayer.Type {
            return cls.init()
        }
        #endif
        // Fallback when the private class is unavailable (or MAS
        // build): a plain CALayer renders nothing, so the chrome
        // silently degrades to no material rather than crashing.
        return CALayer()
    }

    func apply(cornerRadius: CGFloat, blurRadius: Double, saturation: Double) {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.filters = makeFilters(blurRadius: blurRadius, saturation: saturation)
    }

    private func makeFilters(blurRadius: Double, saturation: Double) -> [Any] {
        #if APP_STORE_SANDBOX
        // No `CAFilter` private class on the MAS build, returns no
        // filters. Combined with the plain `CALayer` backing above,
        // the chrome shows whatever SwiftUI material was declared.
        return []
        #else
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else {
            return []
        }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector) else { return [] }

        var filters: [Any] = []
        if let blur = filterInstance(filterClass: filterClass, selector: selector, type: "gaussianBlur") {
            blur.setValue(blurRadius, forKey: "inputRadius")
            filters.append(blur)
        }
        if let saturate = filterInstance(filterClass: filterClass, selector: selector, type: "colorSaturate") {
            saturate.setValue(saturation, forKey: "inputAmount")
            filters.append(saturate)
        }
        return filters
        #endif
    }

    #if !APP_STORE_SANDBOX
    private func filterInstance(
        filterClass: NSObject.Type,
        selector: Selector,
        type: String
    ) -> NSObject? {
        let result = filterClass.perform(selector, with: type)
        return result?.takeUnretainedValue() as? NSObject
    }
    #endif
}
