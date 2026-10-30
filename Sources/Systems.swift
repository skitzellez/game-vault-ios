// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - the systems it plays, which emulator (libretro core, built into the app) plays each, and
// how a file is known to be a game of that system: its extension, else the name of a folder it sits in.
import SwiftUI

struct GameSystem: Identifiable, Hashable {
    let code: String          // the same codes as the Xbox and Android Game Vault
    let name: String
    let core: String          // framework name in the app's Frameworks folder
    let extensions: [String]
    let folderWords: [String] // a folder named like this holds this system's games (for .zip and shared extensions)
    let thumbs: String        // thumbnails.libretro.com folder
    let pad: PadLayout
    var discs = false         // .cue / .chd in its folder are its discs (else they are PlayStation discs)
    var wholeZip = false      // its .zip games go to the core as they are (arcade sets, DOS games)
    var bios: [String] = []   // it starts only with one of these in the BIOS folder
    var betterCore: (core: String, bios: [String])? = nil   // used instead when one of these BIOS files is there

    var id: String { code }
    static func == (a: GameSystem, b: GameSystem) -> Bool { a.code == b.code }
    func hash(into h: inout Hasher) { h.combine(code) }

    var accent: Color {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch code {   // the same colours as the Xbox Game Vault's AccentOf
        case "PS1": return c(0.62, 0.66, 0.74)
        case "SNES": return c(0.55, 0.45, 0.90)
        case "NES": return c(0.90, 0.18, 0.20)
        case "GBA": return c(0.42, 0.36, 0.88)
        case "GBC": return c(0.95, 0.75, 0.15)
        case "GB": return c(0.55, 0.70, 0.25)
        case "MD", "32X", "SCD": return c(0.15, 0.45, 0.95)
        case "SAT": return c(0.30, 0.55, 0.95)
        case "SMS", "GG": return c(0.25, 0.55, 0.95)
        case "PCE", "PCECD": return c(0.95, 0.45, 0.20)
        case "A26", "A52", "A78", "LYNX": return c(0.95, 0.50, 0.20)
        case "VB": return c(0.90, 0.18, 0.20)
        case "ARC": return c(1.0, 0.22, 0.62)
        case "DOS": return c(0.98, 0.74, 0.18)
        default: return Theme.blue
        }
    }
}

// Which touch buttons a system shows, and the libretro button each one presses.
enum PadLayout {
    case twoButtons      // NES, Game Boy, Master System, Game Gear, PC Engine, Lynx, Neo Geo Pocket, WonderSwan
    case gba             // A B L R
    case snes            // A B X Y L R
    case genesis         // A B C
    case saturn          // A B C X Y Z L R
    case arcade          // six buttons + COIN
    case playstation     // cross circle square triangle L1 R1 L2 R2
    case atari           // one fire button
    case virtualBoy      // A B L R
}

enum Systems {
    static let all: [GameSystem] = [
        GameSystem(code: "NES", name: "NES", core: "fceumm_libretro", extensions: ["nes", "fds", "unf", "unif"],
                   folderWords: ["nes", "famicom", "nintendo entertainment system"],
                   thumbs: "Nintendo - Nintendo Entertainment System", pad: .twoButtons),
        GameSystem(code: "SNES", name: "Super Nintendo", core: "snes9x_libretro", extensions: ["sfc", "smc"],
                   folderWords: ["snes", "super nintendo", "super famicom", "sfc"],
                   thumbs: "Nintendo - Super Nintendo Entertainment System", pad: .snes),
        GameSystem(code: "GBA", name: "Game Boy Advance", core: "mgba_libretro", extensions: ["gba"],
                   folderWords: ["gba", "game boy advance", "gameboy advance"],
                   thumbs: "Nintendo - Game Boy Advance", pad: .gba),
        GameSystem(code: "GBC", name: "Game Boy Color", core: "gambatte_libretro", extensions: ["gbc"],
                   folderWords: ["gbc", "game boy color", "gameboy color"],
                   thumbs: "Nintendo - Game Boy Color", pad: .twoButtons),
        GameSystem(code: "GB", name: "Game Boy", core: "gambatte_libretro", extensions: ["gb"],
                   folderWords: ["gb", "game boy", "gameboy"],
                   thumbs: "Nintendo - Game Boy", pad: .twoButtons),
        GameSystem(code: "PS1", name: "PlayStation", core: "pcsx_rearmed_libretro",
                   extensions: ["cue", "chd", "pbp", "m3u", "ccd"],
                   folderWords: ["ps1", "psx", "playstation", "psone"],
                   thumbs: "Sony - PlayStation", pad: .playstation),
        GameSystem(code: "SAT", name: "Saturn", core: "yabause_libretro", extensions: [],
                   folderWords: ["saturn", "sega saturn", "sat"],
                   thumbs: "Sega - Saturn", pad: .saturn, discs: true,
                   betterCore: ("mednafen_saturn_libretro", ["sega_101.bin", "mpr-17933.bin"])),
        GameSystem(code: "MD", name: "Genesis / Mega Drive", core: "genesis_plus_gx_libretro",
                   extensions: ["md", "gen", "smd"],
                   folderWords: ["genesis", "mega drive", "megadrive", "md"],
                   thumbs: "Sega - Mega Drive - Genesis", pad: .genesis),
        GameSystem(code: "SCD", name: "Sega CD", core: "genesis_plus_gx_libretro", extensions: [],
                   folderWords: ["sega cd", "segacd", "mega cd", "megacd", "mega-cd", "scd"],
                   thumbs: "Sega - Mega-CD - Sega CD", pad: .genesis, discs: true,
                   bios: ["bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin"]),
        GameSystem(code: "32X", name: "Sega 32X", core: "picodrive_libretro", extensions: ["32x"],
                   folderWords: ["32x", "sega 32x"],
                   thumbs: "Sega - 32X", pad: .genesis),
        GameSystem(code: "SMS", name: "Master System", core: "genesis_plus_gx_libretro", extensions: ["sms"],
                   folderWords: ["master system", "mastersystem", "sms"],
                   thumbs: "Sega - Master System - Mark III", pad: .twoButtons),
        GameSystem(code: "GG", name: "Game Gear", core: "genesis_plus_gx_libretro", extensions: ["gg"],
                   folderWords: ["game gear", "gamegear", "gg"],
                   thumbs: "Sega - Game Gear", pad: .twoButtons),
        GameSystem(code: "ARC", name: "Arcade", core: "fbneo_libretro", extensions: [],
                   folderWords: ["arcade", "fbneo", "fba", "finalburn", "mame", "neogeo", "neo geo", "cps1", "cps2",
                                 "cps3"],
                   thumbs: "FBNeo - Arcade Games", pad: .arcade, wholeZip: true),
        GameSystem(code: "PCE", name: "TurboGrafx-16", core: "mednafen_pce_fast_libretro", extensions: ["pce"],
                   folderWords: ["pc engine", "pcengine", "turbografx", "turbografx-16", "tg16", "pce"],
                   thumbs: "NEC - PC Engine - TurboGrafx 16", pad: .twoButtons),
        GameSystem(code: "PCECD", name: "TurboGrafx-CD", core: "mednafen_pce_fast_libretro", extensions: [],
                   folderWords: ["pc engine cd", "pcengine cd", "pce-cd", "pcecd", "turbografx cd", "turbografx-cd",
                                 "tg-cd", "tgcd"],
                   thumbs: "NEC - PC Engine CD - TurboGrafx-CD", pad: .twoButtons, discs: true,
                   bios: ["syscard3.pce"]),
        GameSystem(code: "NGP", name: "Neo Geo Pocket", core: "mednafen_ngp_libretro", extensions: ["ngp"],
                   folderWords: ["neo geo pocket", "ngp"],
                   thumbs: "SNK - Neo Geo Pocket", pad: .twoButtons),
        GameSystem(code: "NGPC", name: "Neo Geo Pocket Color", core: "mednafen_ngp_libretro", extensions: ["ngc"],
                   folderWords: ["neo geo pocket color", "ngpc"],
                   thumbs: "SNK - Neo Geo Pocket Color", pad: .twoButtons),
        GameSystem(code: "WS", name: "WonderSwan", core: "mednafen_wswan_libretro", extensions: ["ws"],
                   folderWords: ["wonderswan", "ws"],
                   thumbs: "Bandai - WonderSwan", pad: .twoButtons),
        GameSystem(code: "WSC", name: "WonderSwan Color", core: "mednafen_wswan_libretro", extensions: ["wsc"],
                   folderWords: ["wonderswan color", "wsc"],
                   thumbs: "Bandai - WonderSwan Color", pad: .twoButtons),
        GameSystem(code: "A26", name: "Atari 2600", core: "stella_libretro", extensions: ["a26"],
                   folderWords: ["2600", "atari 2600", "atari2600"],
                   thumbs: "Atari - 2600", pad: .atari),
        GameSystem(code: "A52", name: "Atari 5200", core: "a5200_libretro", extensions: ["a52"],
                   folderWords: ["5200", "atari 5200", "atari5200"],
                   thumbs: "Atari - 5200", pad: .twoButtons),
        GameSystem(code: "A78", name: "Atari 7800", core: "prosystem_libretro", extensions: ["a78"],
                   folderWords: ["7800", "atari 7800", "atari7800"],
                   thumbs: "Atari - 7800", pad: .twoButtons),
        GameSystem(code: "LYNX", name: "Atari Lynx", core: "handy_libretro", extensions: ["lnx"],
                   folderWords: ["lynx"],
                   thumbs: "Atari - Lynx", pad: .twoButtons),
        GameSystem(code: "COL", name: "ColecoVision", core: "gearcoleco_libretro", extensions: ["col"],
                   folderWords: ["colecovision", "coleco"],
                   thumbs: "Coleco - ColecoVision", pad: .twoButtons, bios: ["colecovision.rom"]),
        GameSystem(code: "VB", name: "Virtual Boy", core: "mednafen_vb_libretro", extensions: ["vb", "vboy"],
                   folderWords: ["virtual boy", "virtualboy", "vb"],
                   thumbs: "Nintendo - Virtual Boy", pad: .virtualBoy),
        GameSystem(code: "MIN", name: "Pokémon mini", core: "pokemini_libretro", extensions: ["min"],
                   folderWords: ["pokemon mini", "pokemini"],
                   thumbs: "Nintendo - Pokemon Mini", pad: .twoButtons),
        GameSystem(code: "DOS", name: "DOS", core: "dosbox_pure_libretro", extensions: ["dosz"],
                   folderWords: ["dos", "ms-dos", "msdos"],
                   thumbs: "DOS", pad: .snes, wholeZip: true),
    ]

    static func byCode(_ code: String) -> GameSystem? { all.first { $0.code == code } }

    static func byExtension(_ ext: String) -> GameSystem? {
        let e = ext.lowercased()
        return all.first { $0.extensions.contains(e) }
    }

    // The system a folder path names, from the nearest folder up ("Games/SNES/RPGs/x.zip" -> SNES).
    static func byFolders(_ folders: [String]) -> GameSystem? {
        for folder in folders.reversed() {
            let f = folder.lowercased().trimmingCharacters(in: .whitespaces)
            if let s = all.first(where: { $0.folderWords.contains(f) }) { return s }
        }
        return nil
    }

    static let discExtensions: Set<String> = ["cue", "chd", "m3u", "ccd"]

    // Arcade .zip files that are a BIOS or shared parts, not a game.
    static let arcadeBios: Set<String> = ["neogeo", "pgm", "skns", "decocass", "isgsm", "nmk004", "qsound", "ym2608",
                                          "cps3", "hiscore", "bubsys", "cchip", "ym2413", "midssio", "namcoc69",
                                          "namcoc70", "namcoc75", "neocdz", "coleco", "spectrum", "msx"]
}
