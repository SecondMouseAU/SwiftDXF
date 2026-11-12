import Foundation

extension DXF.Drawing.Counts {
    /// Counts one more entity of the same type as `entity`.
    mutating func record(_ entity: DXF.Entity) {
        switch entity {
        case .line: line += 1
        case .circle: circle += 1
        case .arc: arc += 1
        case .ellipse: ellipse += 1
        case .point: point += 1
        case .text: text += 1
        case .polyline: polyline += 1
        case .dimension: dimension += 1
        case .spline: spline += 1
        case .hatch: hatch += 1
        case .leader: leader += 1
        }
    }
}

extension DXF.Reader {
    /// The entities of one run of records: model space, or the body of one block.
    struct EntityRun {
        var entities: [DXF.Entity] = []
        /// One identity per entry in `entities`.
        var identities: [DXF.Identity] = []
        /// One line type name (group 6) per entry in `entities`, `nil` when the entity has none.
        var lineTypes: [String?] = []
        var counts = DXF.Drawing.Counts()
        var skipped: [String: Int] = [:]
        var skippedByLayer: [String: [String: Int]] = [:]
        /// The `INSERT`s of the run.
        ///
        /// Each is also counted in `skipped`, until an expansion takes it out.
        var references: [DXF.BlockReference] = []
        /// Entities flagged as paper space (group 67), by type.
        ///
        /// Only counted in model space.
        var paperSpace: [String: Int] = [:]
        /// Records written in an object coordinate system whose normal is not along z, by type.
        var tilted: [String: Int] = [:]
        /// Index of the pair that ended the run.
        var end = 0
    }

    /// Reads entities from `start` until a record named in `terminators`.
    ///
    /// `locator` names the position of the n-th top-level record, counting every record (also the
    /// ones that are skipped) so the name does not depend on which types are modelled.
    ///
    /// In `inModelSpace`, entities flagged as paper space are counted, and left out when
    /// ``ReadOptions/skipPaperSpace`` is set.
    func readEntities(
        from start: Int, stopAt terminators: Set<String>, inModelSpace: Bool = false,
        locator: (Int) -> String
    ) -> EntityRun {
        var run = EntityRun()
        var position = 0
        var i = start
        while i < pairs.count {
            let p = pairs[i]
            guard p.code == 0 else {
                i += 1
                continue
            }
            let type = trimmed(p.value)
            if terminators.contains(type) { break }

            // Collect this entity's fields up to the next 0-tag.
            var (fields, j) = recordFields(after: i)

            if inModelSpace, ints(67, fields) == 1 {
                run.paperSpace[type, default: 0] += 1
                if options.skipPaperSpace {
                    position += 1
                    i = j
                    continue
                }
            }
            // The plane of a record written in an OCS; the rest are in the world.
            let plane = usesObjectCoordinates(type, fields) ? objectPlane(fields) : .up
            if let entity = readEntity(type: type, fields: fields, plane: plane, next: &j) {
                if plane == .tilted { run.tilted[type, default: 0] += 1 }
                run.entities.append(entity)
                run.identities.append(
                    DXF.Identity(handle: handle(fields), locator: locator(position)))
                run.lineTypes.append(
                    first(6, fields).map(trimmed).flatMap { $0.isEmpty ? nil : $0 })
                run.counts.record(entity)
                position += 1
            } else if type != "VERTEX" && type != "SEQEND" {
                // Unmodelled entity (INSERT, SOLID, TRACE, …): skip, but record it.
                if type == "INSERT" {
                    let identity = DXF.Identity(handle: handle(fields), locator: locator(position))
                    run.references.append(blockReference(fields, identity: identity))
                }
                run.skipped[type, default: 0] += 1
                run.skippedByLayer[type, default: [:]][layer(fields), default: 0] += 1
                position += 1
            }
            i = j
        }
        run.end = i
        return run
    }

    /// The pairs after the `0` tag at `tag`, up to the next `0` tag, and the index that stops at.
    func recordFields(after tag: Int) -> (fields: [(code: Int, value: String)], end: Int) {
        var end = tag + 1
        var fields: [(code: Int, value: String)] = []
        while end < pairs.count && pairs[end].code != 0 {
            fields.append(pairs[end])
            end += 1
        }
        return (fields, end)
    }

    /// The handle in group `code` (5 for most records, 105 for a dimension style), or `nil`.
    func handle(_ f: [(code: Int, value: String)], code: Int = 5) -> String? {
        guard let value = first(code, f).map(trimmed), !value.isEmpty else { return nil }
        return value
    }

    /// One entity from its fields, in world coordinates, or `nil` for a type that is not modelled.
    ///
    /// `next` is the index of the pair after the record, and moves forward when the record owns
    /// following records (a `POLYLINE` owns its `VERTEX` run and the `SEQEND`).
    private func readEntity(
        type: String, fields: [(code: Int, value: String)], plane: DXF.ObjectPlane,
        next j: inout Int
    ) -> DXF.Entity? {
        guard let entity = readRecord(type: type, fields: fields, plane: plane, next: &j)
        else { return nil }
        return inWorld(entity, plane: plane)
    }

    /// One entity from its fields as written, which for some types is in the object coordinate
    /// system; see ``readEntity(type:fields:plane:next:)``.
    private func readRecord(
        type: String, fields: [(code: Int, value: String)], plane: DXF.ObjectPlane,
        next j: inout Int
    ) -> DXF.Entity? {
        switch type {
        case "LINE":
            let a = point(fields)
            let b = DXF.Point(dbl(11, fields), dbl(21, fields), dbl(31, fields))
            return .line(a: a, b: b, layer: layer(fields), color: color(fields))

        case "CIRCLE":
            return .circle(
                center: point(fields), radius: dbl(40, fields),
                layer: layer(fields), color: color(fields))

        case "ARC":
            return .arc(
                center: point(fields), radius: dbl(40, fields),
                startDeg: dbl(50, fields), endDeg: dbl(51, fields),
                layer: layer(fields), color: color(fields))

        case "ELLIPSE":
            var major = DXF.Point(dbl(11, fields), dbl(21, fields), dbl(31, fields))
            var ratio = dbl(40, fields, 1)
            var startP = dbl(41, fields, 0)
            var endP = dbl(42, fields, 2 * .pi)
            // An extrusion of -z makes the parameter run clockwise; turn it into the same curve
            // running counter-clockwise, before the ratio is normalised below.
            if plane == .down {
                (startP, endP) = Self.mirroredEllipseRange(start: startP, end: endP)
            }
            // The DXF spec requires ratio = minor/major ≤ 1. Some writers emit ratio > 1
            // (a swapped major axis). Normalise to the canonical form: rotate the major axis
            // +90° and scale by ratio, invert the ratio, shift the params by −π/2, so the curve
            // is unchanged but downstream consumers (e.g. OCCT's Geom_Ellipse, which demands
            // majorRadius ≥ minorRadius) get a valid axis. Matches ezdxf's normalisation.
            if ratio > 1 {
                major = DXF.Point(-major.y * ratio, major.x * ratio, major.z)
                ratio = 1 / ratio
                func shift(_ a: Double) -> Double {
                    let m = (a - .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
                    return m < 0 ? m + 2 * .pi : m
                }
                startP = shift(startP)
                endP = shift(endP)
            }
            return .ellipse(
                center: point(fields), majorAxis: major,
                ratio: ratio, startParam: startP, endParam: endP,
                layer: layer(fields), color: color(fields))

        case "POINT":
            return .point(at: point(fields), layer: layer(fields), color: color(fields))

        case "TEXT", "MTEXT":
            return .text(
                at: point(fields), height: dbl(40, fields, 0),
                rotationDeg: dbl(50, fields, 0), string: textValue(fields),
                layer: layer(fields), color: color(fields))

        case "LWPOLYLINE":
            // Vertices interleave in order: 10 x, 20 y, optional 42 bulge; a new 10 starts the
            // next vertex. Walk in field order so each bulge binds to its own vertex.
            let closed = (ints(70, fields) ?? 0) & 1 == 1
            return .polyline(
                vertices: lwVertices(fields), closed: closed,
                layer: layer(fields), color: color(fields))

        case "POLYLINE":
            // Old-style: a POLYLINE header followed by VERTEX entities and a terminating SEQEND.
            let flags = ints(70, fields) ?? 0
            let closed = flags & 1 == 1
            // A 2D polyline's elevation (group 30 of the header) is the z of every vertex, as in
            // ezdxf; a 3D polyline, polygon mesh or polyface mesh has none.
            let elevation = flags & (8 | 16 | 64) == 0 ? dbl(30, fields) : 0
            var verts: [DXF.PolyVertex] = []
            while j < pairs.count && pairs[j].code == 0 && trimmed(pairs[j].value) == "VERTEX" {
                var m = j + 1
                var vf: [(code: Int, value: String)] = []
                while m < pairs.count && pairs[m].code != 0 {
                    vf.append(pairs[m])
                    m += 1
                }
                var location = point(vf)
                if elevation != 0 { location.z = elevation }
                verts.append(DXF.PolyVertex(location, bulge: dbl(42, vf, 0)))
                j = m
            }
            if j < pairs.count && pairs[j].code == 0 && trimmed(pairs[j].value) == "SEQEND" {
                var m = j + 1
                while m < pairs.count && pairs[m].code != 0 { m += 1 }
                j = m
            }
            return .polyline(
                vertices: verts, closed: closed, layer: layer(fields), color: color(fields))

        case "DIMENSION":
            return .dimension(dimension(fields))

        case "SPLINE":
            return .spline(
                DXF.Spline(
                    degree: ints(71, fields) ?? 3, flags: ints(70, fields) ?? 0,
                    controlPoints: splinePoints(10, fields),
                    knots: allDbl(40, fields), weights: allDbl(41, fields),
                    fitPoints: splinePoints(11, fields),
                    layer: layer(fields), color: color(fields)))

        case "HATCH":
            return .hatch(hatch(fields))

        case "LEADER":
            return .leader(leader(fields))

        default:
            return nil
        }
    }
}
