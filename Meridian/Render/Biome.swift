import SpriteKit
import MeridianCore

/// Per-map visual identity. Purely cosmetic: palettes, water style, wind, ambient particles and decor tints.
/// All three share the "Twilight Frontier" art direction but read as different places on the same planet.
struct Biome {
    enum Ambient { case pollen, mist, dust }

    var name: String
    var grassA: SIMD3<Float>, grassB: SIMD3<Float>, dry: SIMD3<Float>
    var mossA: SIMD3<Float>, mossB: SIMD3<Float>
    var dirtA: SIMD3<Float>, dirtB: SIMD3<Float>
    var rockA: SIMD3<Float>, rockB: SIMD3<Float>
    var waterS: SIMD3<Float>, waterD: SIMD3<Float>
    /// 0 = ordinary water, 1 = luminous mineral pools.
    var waterGlow: Float
    /// Direction and speed of surface flow (world units/s).
    var flow: SIMD2<Float>
    var flowerA: SIMD3<Float>, flowerB: SIMD3<Float>
    var grade: SIMD3<Float>, lift: SIMD3<Float>
    /// Wind direction (world units/s) for gust bands sweeping the grass, and their strength.
    var wind: SIMD2<Float>, gust: Float
    /// Dried-mud cracks in dirt.
    var cracks: Float
    var abyss: SIMD3<Float>
    var ambient: Ambient
    var moteColor: SKColor
    /// Tints for decor sprites (trees, flora, cliffs).
    var treeTint: SKColor, treeTintAmount: CGFloat
    var floraTint: SKColor
    var cliffTint: SKColor, cliffTintAmount: CGFloat
    var cloudAlpha: CGFloat

    static func of(_ layout: MapLayout) -> Biome {
        switch layout {
        case .riverbend: return .delta
        case .highlands: return .highlands
        default: return .meadow
        }
    }

    /// Crossroads: amber meadows at dusk (the original look, now with wind and pollen).
    static let meadow = Biome(
        name: "Amber Meadows",
        grassA: [0.20, 0.36, 0.19], grassB: [0.42, 0.52, 0.22], dry: [0.50, 0.50, 0.24],
        mossA: [0.09, 0.27, 0.28], mossB: [0.18, 0.40, 0.35],
        dirtA: [0.40, 0.29, 0.20], dirtB: [0.62, 0.47, 0.30],
        rockA: [0.26, 0.23, 0.27], rockB: [0.44, 0.39, 0.40],
        waterS: [0.13, 0.42, 0.48], waterD: [0.04, 0.16, 0.30], waterGlow: 0, flow: [0.25, 0.12],
        flowerA: [1.0, 0.82, 0.35], flowerB: [0.75, 0.55, 1.0],
        grade: [1.06, 1.0, 0.94], lift: [0.0, 0.01, 0.03],
        wind: [0.9, -0.5], gust: 1.0, cracks: 0,
        abyss: [0.10, 0.12, 0.16], ambient: .pollen,
        moteColor: SKColor(red: 1, green: 0.85, blue: 0.55, alpha: 1),
        treeTint: .white, treeTintAmount: 0,
        floraTint: SKColor(red: 0.2, green: 0.25, blue: 0.2, alpha: 1),
        cliffTint: .white, cliffTintAmount: 0, cloudAlpha: 0.32)

    /// Riverbend: a humid river delta; deep greens, mossy stone, a flowing river and drifting mist.
    static let delta = Biome(
        name: "Verdant Delta",
        grassA: [0.12, 0.29, 0.20], grassB: [0.27, 0.43, 0.23], dry: [0.38, 0.44, 0.26],
        mossA: [0.05, 0.24, 0.26], mossB: [0.12, 0.36, 0.34],
        dirtA: [0.29, 0.24, 0.18], dirtB: [0.45, 0.37, 0.25],
        rockA: [0.21, 0.25, 0.26], rockB: [0.37, 0.41, 0.41],
        waterS: [0.09, 0.44, 0.42], waterD: [0.02, 0.17, 0.24], waterGlow: 0, flow: [0.05, 0.55],
        flowerA: [0.70, 0.88, 1.0], flowerB: [1.0, 0.95, 0.85],
        grade: [0.99, 1.0, 1.02], lift: [0.0, 0.015, 0.035],
        wind: [0.4, 0.7], gust: 0.8, cracks: 0,
        abyss: [0.06, 0.11, 0.13], ambient: .mist,
        moteColor: SKColor(red: 0.75, green: 1, blue: 0.55, alpha: 1),
        treeTint: SKColor(red: 0.25, green: 0.65, blue: 0.55, alpha: 1), treeTintAmount: 0.18,
        floraTint: SKColor(red: 0.15, green: 0.3, blue: 0.25, alpha: 1),
        cliffTint: SKColor(red: 0.45, green: 0.62, blue: 0.5, alpha: 1), cliffTintAmount: 0.22, cloudAlpha: 0.38)

    /// Shattered Highlands: a wind-scoured rust plateau with violet lichen and luminous mineral pools.
    static let highlands = Biome(
        name: "Rust Plateau",
        grassA: [0.36, 0.34, 0.18], grassB: [0.55, 0.48, 0.25], dry: [0.68, 0.53, 0.30],
        mossA: [0.27, 0.22, 0.27], mossB: [0.40, 0.31, 0.38],
        dirtA: [0.47, 0.29, 0.19], dirtB: [0.68, 0.46, 0.29],
        rockA: [0.35, 0.25, 0.24], rockB: [0.56, 0.42, 0.36],
        waterS: [0.22, 0.78, 0.72], waterD: [0.10, 0.28, 0.46], waterGlow: 1, flow: [0.08, 0.05],
        flowerA: [1.0, 0.55, 0.3], flowerB: [0.85, 0.6, 1.0],
        grade: [1.08, 0.98, 0.9], lift: [0.02, 0.0, 0.03],
        wind: [1.6, -0.6], gust: 1.3, cracks: 1,
        abyss: [0.14, 0.09, 0.10], ambient: .dust,
        moteColor: SKColor(red: 1, green: 0.7, blue: 0.45, alpha: 1),
        treeTint: SKColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1), treeTintAmount: 0.3,
        floraTint: SKColor(red: 0.45, green: 0.3, blue: 0.18, alpha: 1),
        cliffTint: SKColor(red: 0.85, green: 0.5, blue: 0.38, alpha: 1), cliffTintAmount: 0.3, cloudAlpha: 0.22)
}
