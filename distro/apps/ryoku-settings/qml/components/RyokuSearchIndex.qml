import QtQuick

/*
  In-memory search over page titles and option labels.

  Entries reuse each page's own qsTr() source strings and are translated with
  qsTranslate(<page file>, …), so results read exactly like the UI and need no
  extra catalogue entries. tests/test_parsers.cpp fails if an entry no longer
  exists in its page or in the PT-BR catalogue.

  `reveal` names page state a result needs (see AppearancePage.revealSearchTarget).
*/
QtObject {
    id: index

    readonly property var pageContexts: ({
        home: "HomePage",
        appearance: "AppearancePage",
        network: "NetworkPage",
        bluetooth: "BluetoothPage",
        sound: "SoundPage",
        displays: "DisplaysPage",
        power: "PowerPage",
        apps: "AppsPage",
        system: "SystemPage",
        nix: "NixUpdatesPage",
        about: "AboutPage"
    })

    readonly property var entries: [
        { page: "home", text: QT_TRANSLATE_NOOP("HomePage", "Quick access") },
        { page: "home", text: QT_TRANSLATE_NOOP("HomePage", "System state") },

        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Wallpaper") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Gallery") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Image") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Video") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Video wallpaper"), reveal: "video" },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Loop"), reveal: "video" },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Audio"), reveal: "video" },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Pause when covered"), reveal: "video" },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Performance"), reveal: "video" },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Login screen wallpaper") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Material You") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Dynamic colors") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Shell style") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Visual effects") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Cinematic") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Automatic on battery") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Animations") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Language") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Transparency") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Themes & fonts") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Icons") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Cursor") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "UI Font") },
        { page: "appearance", text: QT_TRANSLATE_NOOP("AppearancePage", "Mono Font") },

        { page: "network", text: QT_TRANSLATE_NOOP("NetworkPage", "Wi-Fi") },
        { page: "network", text: QT_TRANSLATE_NOOP("NetworkPage", "Wireless radio") },
        { page: "network", text: QT_TRANSLATE_NOOP("NetworkPage", "Available networks") },

        { page: "bluetooth", text: QT_TRANSLATE_NOOP("BluetoothPage", "Adapter") },
        { page: "bluetooth", text: QT_TRANSLATE_NOOP("BluetoothPage", "My devices") },
        { page: "bluetooth", text: QT_TRANSLATE_NOOP("BluetoothPage", "Nearby") },

        { page: "sound", text: QT_TRANSLATE_NOOP("SoundPage", "Output") },
        { page: "sound", text: QT_TRANSLATE_NOOP("SoundPage", "Volume") },
        { page: "sound", text: QT_TRANSLATE_NOOP("SoundPage", "Input") },
        { page: "sound", text: QT_TRANSLATE_NOOP("SoundPage", "Input volume") },
        { page: "sound", text: QT_TRANSLATE_NOOP("SoundPage", "Devices") },

        { page: "displays", text: QT_TRANSLATE_NOOP("DisplaysPage", "Monitors") },
        { page: "displays", text: QT_TRANSLATE_NOOP("DisplaysPage", "Layout") },
        { page: "displays", text: QT_TRANSLATE_NOOP("DisplaysPage", "Resolution / Refresh") },
        { page: "displays", text: QT_TRANSLATE_NOOP("DisplaysPage", "Scale") },
        { page: "displays", text: QT_TRANSLATE_NOOP("DisplaysPage", "Position") },

        { page: "power", text: QT_TRANSLATE_NOOP("PowerPage", "Power profile") },
        { page: "power", text: QT_TRANSLATE_NOOP("PowerPage", "Display brightness") },
        { page: "power", text: QT_TRANSLATE_NOOP("PowerPage", "Battery") },
        { page: "power", text: QT_TRANSLATE_NOOP("PowerPage", "Sleep & lid") },
        { page: "power", text: QT_TRANSLATE_NOOP("PowerPage", "Lid close") },
        { page: "power", text: QT_TRANSLATE_NOOP("PowerPage", "Suspend") },
        { page: "power", text: QT_TRANSLATE_NOOP("PowerPage", "Idle") },

        { page: "apps", text: QT_TRANSLATE_NOOP("AppsPage", "Managed by Ryoku") },
        { page: "apps", text: QT_TRANSLATE_NOOP("AppsPage", "Installed locally") },
        { page: "apps", text: QT_TRANSLATE_NOOP("AppsPage", "Add Flatpak") },

        { page: "system", text: QT_TRANSLATE_NOOP("SystemPage", "Operating system") },
        { page: "system", text: QT_TRANSLATE_NOOP("SystemPage", "Hardware") },
        { page: "system", text: QT_TRANSLATE_NOOP("SystemPage", "Processor") },
        { page: "system", text: QT_TRANSLATE_NOOP("SystemPage", "Memory") },
        { page: "system", text: QT_TRANSLATE_NOOP("SystemPage", "Kernel") },
        { page: "system", text: QT_TRANSLATE_NOOP("SystemPage", "Hostname") },
        { page: "system", text: QT_TRANSLATE_NOOP("SystemPage", "Uptime") },
        { page: "system", text: QT_TRANSLATE_NOOP("SystemPage", "Session") },

        { page: "nix", text: QT_TRANSLATE_NOOP("NixUpdatesPage", "Git changes") },
        { page: "nix", text: QT_TRANSLATE_NOOP("NixUpdatesPage", "Commit message") },
        { page: "nix", text: QT_TRANSLATE_NOOP("NixUpdatesPage", "Working tree") },
        { page: "nix", text: QT_TRANSLATE_NOOP("NixUpdatesPage", "Flake inputs") },
        { page: "nix", text: QT_TRANSLATE_NOOP("NixUpdatesPage", "Flake lock") },
        { page: "nix", text: QT_TRANSLATE_NOOP("NixUpdatesPage", "Generations") },
        { page: "nix", text: QT_TRANSLATE_NOOP("NixUpdatesPage", "Rebuild hint") },

        { page: "about", text: QT_TRANSLATE_NOOP("AboutPage", "Version") },
        { page: "about", text: QT_TRANSLATE_NOOP("AboutPage", "Repository & stack") },
        { page: "about", text: QT_TRANSLATE_NOOP("AboutPage", "Settings schema") }
    ]

    // Case- and accent-insensitive ("video" finds "Vídeo").
    function normalize(s) {
        return String(s).toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    }

    // Every term must occur in the label, its English source or the page title;
    // label hits rank above source hits, which rank above page-title-only hits.
    // One-letter terms only match at a word start (otherwise "i" matches everything).
    function rank(label, source, pageText, terms) {
        let score = 0
        for (let i = 0; i < terms.length; ++i) {
            const t = terms[i]
            if (label.startsWith(t))
                score += 30
            else if (label.indexOf(" " + t) >= 0)
                score += 22
            else if (t.length < 2)
                return 0
            else if (label.indexOf(t) >= 0)
                score += 15
            else if (source.indexOf(t) >= 0)
                score += 10
            else if (pageText.indexOf(t) >= 0)
                score += 2
            else
                return 0
        }
        return score
    }

    // pages: Main.pages ({ id, source }). Returns results ordered by relevance,
    // then sidebar order: { pageIndex, pageTitle, label, isPage, reveal }.
    function search(query, pages) {
        const q = normalize(query).trim()
        if (!q.length)
            return []
        const terms = q.split(/\s+/)
        const out = []
        const pageIndexById = {}

        for (let i = 0; i < pages.length; ++i) {
            const p = pages[i]
            pageIndexById[p.id] = i
            const title = qsTranslate("Main", p.source)
            const s = index.rank(normalize(title), normalize(p.source), "", terms)
            if (s > 0)
                out.push({ pageIndex: i, pageTitle: title, label: title, isPage: true, reveal: "", score: s + 40 })
        }

        for (let j = 0; j < entries.length; ++j) {
            const e = entries[j]
            const pi = pageIndexById[e.page]
            if (pi === undefined)
                continue
            const p = pages[pi]
            const pageTitle = qsTranslate("Main", p.source)
            const label = qsTranslate(pageContexts[e.page], e.text)
            const s = index.rank(normalize(label), normalize(e.text),
                                 normalize(pageTitle + " " + p.source), terms)
            if (s > 0)
                out.push({ pageIndex: pi, pageTitle: pageTitle, label: label, isPage: false,
                           reveal: e.reveal || "", score: s })
        }

        out.sort(function(a, b) { return (b.score - a.score) || (a.pageIndex - b.pageIndex) })
        return out.slice(0, 40)
    }
}
