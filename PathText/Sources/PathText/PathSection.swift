//
//  File.swift
//  
//
//  Created by Rob Napier on 12/8/19.
//

import CoreGraphics

protocol PathSection {
    var start: CGPoint { get }
    var end: CGPoint { get }
    func getTangent(t: CGFloat) -> PathTangent
    func nextTangent(linearDistance: CGFloat, after: PathTangent) -> NextTangent
}

extension PathSection {
    // Default impl
    func nextTangent(linearDistance: CGFloat, after lastTangent: PathTangent) -> NextTangent {
        // Simplistic routine to find the t along Bezier that is
        // a linear distance away from a previous tangent.
        // This routine just walks forward, accumulating Euclidean approximations until it finds
        // a point at least linearDistance away. Good optimizations here would reduce the number
        // of guesses, but this is tricky since if we go too far out, the
        // curve might loop back on leading to incorrect results. Tuning
        // kStep is good start.
        let point = lastTangent.point

        let step: CGFloat = 0.001 // 0.0001 - 0.001 work well
        var approximateLinearDistance: CGFloat = 0
        var tangent = lastTangent
        while approximateLinearDistance <= linearDistance && tangent.t < 1.0 {
            tangent = getTangent(t: tangent.t + step)
            approximateLinearDistance = point.distance(to: tangent.point) // FIXME: Inefficient?
        }

        if tangent.t >= 1.0 {
            return .insufficient(remainingLinearDistance: approximateLinearDistance)
        } else {
            return .found(tangent)
        }
    }
}

struct PathTangent: Equatable {
    var t: CGFloat
    var point: CGPoint
    var angle: CGFloat
}

enum NextTangent {
    case found(PathTangent)
    case insufficient(remainingLinearDistance: CGFloat)
}

import SwiftUI

@available(iOS 13.0, *)
extension Path {
    func sections() -> [PathSection] {
            var sections: [PathSection] = []
            var start: CGPoint?
            var current: CGPoint?

        self.forEach { element in
            switch element {
            case .move(let to):
                start = start ?? to
                current = to

            case .line(let to):
                sections.append(PathLineSection(start: current ?? .zero, end: to))
                start = start ?? .zero
                current = to

            case .quadCurve(let to, let control):
                sections.append(PathQuadCurveSection(p0: current ?? .zero, p1: control, p2: to))
                start = start ?? .zero
                current = to

            case .curve(let to, let control1, let control2):
                sections.append(PathCurveSection(p0: current ?? .zero, p1: control1, p2: control2, p3: to))
                start = start ?? .zero
                current = to

            case .closeSubpath:
                sections.append(PathLineSection(start: current ?? .zero, end: start ?? .zero))
                current = start
                start = nil
            }
        }

        return sections
    }

    // Locations must be in ascending order
    func getTangents(atLocations locations: [CGFloat]) -> [PathTangent] {
        assert(locations == locations.sorted())

        var tangents: [PathTangent] = []

        var sections = self.sections()[...]
        var locations = locations[...]

        var lastLocation: CGFloat = 0.0
        var lastTangent: PathTangent?

        while let location = locations.first, let section = sections.first  {
            let currentTangent = lastTangent ?? section.getTangent(t: 0)

            guard location != lastLocation else {
                tangents.append(currentTangent)
                locations = locations.dropFirst()
                continue
            }

            let linearDistance = location - lastLocation

            switch section.nextTangent(linearDistance: linearDistance,
                                       after: currentTangent) {
            case .found(let tangent):
                tangents.append(tangent)
                lastTangent = tangent
                lastLocation = location
                locations = locations.dropFirst()

            case .insufficient(remainingLinearDistance: let remaining):
                lastTangent = nil
                lastLocation = location + remaining
                sections = sections.dropFirst()
            }
        }

        return tangents
    }
}

struct PathLineSection: PathSection {
    let start, end: CGPoint

    func getTangent(t: CGFloat) -> PathTangent {
        let dx = end.x - start.x
        let dy = end.y - start.y

        let x = start.x + dx * t
        let y = start.y + dy * t

        return PathTangent(t: t,
                           point: CGPoint(x: x, y: y),
                           angle: atan2(dy, dx))
    }
}

struct PathQuadCurveSection: PathSection {
    let p0, p1, p2: CGPoint
    var start: CGPoint { p0 }
    var end: CGPoint { p2 }

    func getTangent(t: CGFloat) -> PathTangent {
        let dx = bezierPrime(t, p0.x, p1.x, p2.x)
        let dy = bezierPrime(t, p0.y, p1.y, p2.y)

        let x = bezier(t, p0.x, p1.x, p2.x)
        let y = bezier(t, p0.y, p1.y, p2.y)

        return PathTangent(t: t,
                           point: CGPoint(x: x, y: y),
                           angle: atan2(dy, dx))
    }

    // The quadratic Bezier function at t
    private func bezier(_ t: CGFloat, _ P0: CGFloat, _ P1: CGFloat, _ P2: CGFloat) -> CGFloat {
               (1-t)*(1-t)       * P0
         + 2 *       (1-t) *   t * P1
         +                   t*t * P2
    }

    // The slope of the quadratic Bezier function at t
    private func bezierPrime(_ t: CGFloat, _ P0: CGFloat, _ P1: CGFloat, _ P2: CGFloat) -> CGFloat {
          2 * (1-t) * (P1 - P0)
        + 2 * t * (P2 - P1)
    }
}

struct PathCurveSection: PathSection {

    let p0, p1, p2, p3: CGPoint
    var start: CGPoint { p0 }
    var end: CGPoint { p3 }

    func getTangent(t: CGFloat) -> PathTangent {
        let dx = bezierPrime(t, p0.x, p1.x, p2.x, p3.x)
        let dy = bezierPrime(t, p0.y, p1.y, p2.y, p3.y)

        let x = bezier(t, p0.x, p1.x, p2.x, p3.x)
        let y = bezier(t, p0.y, p1.y, p2.y, p3.y)

        return PathTangent(t: t,
                           point: CGPoint(x: x, y: y),
                           angle: atan2(dy, dx))
    }

    // The cubic Bezier function at t
    private func bezier(_ t: CGFloat, _ P0: CGFloat, _ P1: CGFloat, _ P2: CGFloat, _ P3: CGFloat) -> CGFloat {
               (1-t)*(1-t)*(1-t)         * P0
         + 3 *       (1-t)*(1-t) *     t * P1
         + 3 *             (1-t) *   t*t * P2
         +                         t*t*t * P3
    }

    // The slope of the cubic Bezier function at t
    private func bezierPrime(_ t: CGFloat, _ P0: CGFloat, _ P1: CGFloat, _ P2: CGFloat, _ P3: CGFloat) -> CGFloat {
           0
        -  3 * (1-t)*(1-t) * P0
        + (3 * (1-t)*(1-t) * P1) - (6 * t * (1-t) * P1)
        - (3 *         t*t * P2) + (6 * t * (1-t) * P2)
        +  3 * t*t * P3
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return hypot(dx, dy)
    }
}
