//  SettingsMockup.swift
//  Iconik Employee — AMB.12's Settings family, built in batch 4
//
//  ARC SCAFFOLDING. Deleted at AMB.12's close, with the rest of the lab.
//
//  SELF-CONTAINED ON PURPOSE. Nothing here is a production component yet; at the
//  conversion these private types become a `Settings/SettingsKit.swift` the lab
//  then imports, the way Class Groups and Yearbook went at AMB.10.
//
//  WHAT THIS COVERS: the Settings tree is 14 files and 13 View structs, all
//  hanging off ONE hamburger item — there is no `FeatureItem` for settings, so it
//  cannot be pinned to the tab bar, never appears in All Features, and has NO
//  registered FeatureTheme colour (it falls to the map's `default: .gray`). The
//  auth screens are in the same tree by ownership even though a signed-out user
//  reaches them from `RootView`, and the appearance picker is a sheet off the same
//  profile menu. All of it is drawn here.
//
//  WHAT THE DESIGN IS ARGUING, in six claims
//
//      1. SETTINGS HAS A COLOUR, AND IT IS THE COMPANY'S.
//         Every other converted surface washes in its feature's colour (D11).
//         Settings has no feature id to take one from, so it uses
//         `AmbientStyle.brand` — the Iconik blue from the logo — which is what the
//         app already uses when a surface needs to feel like THIS APP rather than
//         like one of its features. That is a deliberate choice, not a default.
//
//      2. THE SYNC BLOCK SAYS WHO IT IS FOR.
//         Device Name, Sync & Cache and Metrics are iPad-sync features shown
//         unconditionally to every iPhone user today, three sections deep in the
//         only screen a photographer opens to change their phone number. They stay
//         — support needs them — but they sit under one heading that says what
//         they are, below the rows people actually touch.
//
//      3. A DESTRUCTIVE ACTION LOOKS DESTRUCTIVE.
//         "Logout" is a plain row with no destructive role, no confirmation and no
//         error path — a failed sign-out is printed to the console and the user
//         stays signed in with no feedback, which on a shared iPad is a
//         PII-retention failure. Meanwhile Resync, which only clears a cache, has
//         both a confirmation and an alert. The two swap places.
//
//      4. EVERY SCREEN THAT CAN FAIL SAYS SO, AND OFFERS A WAY BACK.
//         Exactly ONE retry affordance exists in the whole tree (PTO Balance's).
//         Offline is understood by exactly ONE of the 14 files. School Detail
//         renders its form with an empty name and 0.0 miles until data lands.
//
//      5. A SCHOOL SCREEN IS ABOUT A SCHOOL.
//         `SchoolDetailView` is titled "School Detail", not the school's name, and
//         its rename field re-queries the half-typed name on every keystroke. The
//         name goes in the title; the rename gets a warning, because every
//         school↔report join in this tree is by NAME and renaming orphans the
//         school's whole history.
//
//      6. SIGN-IN IS THE FIRST SCREEN EVERY USER SEES.
//         It is also the only auth screen that routes errors through the app's
//         user-facing error mapper; Create Account prints raw Postgrest text on
//         screen. One error treatment across the four.
//
//  WHAT IS NOT BEING PROPOSED
//      No data layer, service, auth, schema or RLS changes (D12).
//      Specifically NOT promised: changing the account EMAIL (the field writes
//      `users.email` and Supabase Auth's email is never touched — the two diverge
//      and sign-in still needs the old address; the field is drawn read-only with
//      that said out loud), MULTI-DAY metrics export (`listFiles()` has zero call
//      sites; only today's file is ever shareable and it may not exist), photo
//      CROP or DELETE on the profile photo screen, editing a school's
//      COORDINATES (`updateSchool` is not called with them, so a mis-geocoded
//      school is unfixable from iOS), and any per-item permission gate — there is
//      no client-side permission check anywhere in this tree and this design does
//      not invent the impression of one.
//      NOT REDESIGNED: `PTOBalanceView`. It lives in `Settings/` but was converted
//      by AMB.8 and is already Ambient; it is referenced here and left alone.
//      NOT COVERED BY ANY PHASE, and stated so it is not mistaken for done: the
//      TIME-TRACKING surface — ten screens, 2,662 lines, seven payroll write paths
//      and exactly one confirmation between them — is named in no phase in the
//      arc, and AMB.12 is the last phase in which that can be answered.
//
//  VOCABULARY COMES FROM PRODUCTION
//      Every string below is the shipped string. Where a sentence is new it is
//      captioned PROPOSED, because in this tree a sentence IS the feature: the
//      resync footer, the PTO "hours used" caption and the 48-hour clock-in note
//      are all load-bearing copy.

import SwiftUI

// MARK: - Lab state

private enum SettingsLabSurface: String, CaseIterable, Identifiable {
    case root = "Settings"
    case account = "Account"
    case photo = "Photo"
    case schools = "Schools"
    case school = "School"
    case metrics = "Metrics"
    case auth = "Sign in"
    case appearance = "Theme"

    var id: String { rawValue }
}

private enum SettingsLabAuthScreen: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case create = "Create"
    case forgot = "Forgot"
    case reset = "Reset"

    var id: String { rawValue }
}

private enum SettingsLabState: String, CaseIterable, Identifiable {
    case ready = "Ready"
    case loading = "Loading"
    case failed = "Failed"
    case offline = "Offline"

    var id: String { rawValue }
}

// MARK: - Root

struct SettingsMockup: View {
    /// Settings has NO registered FeatureTheme colour — there is no `"settings"`
    /// case in the map, so `FeatureTheme.color(for:)` returns its `default: .gray`.
    /// The company blue is the deliberate answer (claim 1).
    static var featureTint: Color { AmbientStyle.brand }

    @State private var surface: SettingsLabSurface = .root
    @State private var state: SettingsLabState = .ready

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · screen", trailing: "not a design element")
            Picker("Screen", selection: $surface) {
                ForEach(SettingsLabSurface.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if surface == .root || surface == .schools || surface == .school {
                Picker("State", selection: $state) {
                    ForEach(SettingsLabState.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch surface {
        case .root: SettingsLabRoot(state: state)
        case .account: SettingsLabAccount()
        case .photo: SettingsLabPhoto()
        case .schools: SettingsLabSchools(state: state)
        case .school: SettingsLabSchoolDetail(state: state)
        case .metrics: SettingsLabMetrics()
        case .auth: SettingsLabAuth()
        case .appearance: SettingsLabAppearance()
        }
    }
}

// MARK: - The root list

private struct SettingsLabRoot: View {
    let state: SettingsLabState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 2 — the rows a photographer actually opens, first.
            VStack(alignment: .leading, spacing: 10) {
                AmbientSectionTitle("You")
                SettingsLabRow(title: "Account Info",
                               detail: "Name, phone, address, position",
                               symbol: "person.crop.circle")
                SettingsLabRow(title: "Profile Photo",
                               detail: "Shown on the schedule and in chat",
                               symbol: "photo")
                SettingsLabRow(title: "PTO Balance",
                               detail: "Hours available, accrual, projection",
                               symbol: "clock.fill")
                SettingsLabRow(title: "School Info",
                               detail: "\(DesignLabSampleData.schoolsInfo.count) schools · addresses, mileage, location photos",
                               symbol: "building.2")
                SettingsLabRow(title: "Quick Access Tab Bar",
                               detail: "Choose and reorder the bottom bar",
                               symbol: "square.grid.2x2")
                SettingsLabRow(title: "Appearance",
                               detail: "System, Light or Dark",
                               symbol: "paintbrush")
            }

            Text("\"Appearance\" moves INTO Settings. It is a sheet off the profile hamburger today, beside \"Settings\" itself — two entries in one menu where one of them is a settings screen. PTO Balance is unchanged: it was converted by AMB.8 and this design does not touch it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            // 2 — the iPad sync block, under a heading that says what it is.
            VStack(alignment: .leading, spacing: 10) {
                AmbientSectionTitle("This device", trailing: state == .offline ? "offline" : "synced")

                AmbientFormSection(title: "Device name",
                                   status: "Kiosk",
                                   statusTint: nil) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("e.g. Kiosk, Poser, Camera 2", text: .constant("Kiosk"))
                            .font(.subheadline)
                        Text("Shown to other devices on the local network. Use this to tell iPads apart in the disconnect warning and the device list. Leave blank to use the iPad's system name. Reconnect on the Sync sheet (or restart the app) for a name change to take effect.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                AmbientFormSection(title: "Sync & cache",
                                   status: state == .offline ? "Offline" : "Synced",
                                   statusTint: state == .offline ? .orange : .green) {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsLabStatLine(label: "Status",
                                            value: state == .offline ? "Offline" : "Synced")
                        SettingsLabStatLine(label: "Last synced", value: "2 min ago")
                        if state == .failed {
                            SettingsLabStatLine(label: "Last error",
                                                value: "connection lost (code 53)")
                        }
                        Divider()
                        Text(state == .offline
                             ? "Resync is disabled while offline. Connect to Wi-Fi first — clearing the local cache without a connection would leave the device with no data."
                             : "Use only when this device is missing data that you can see on other devices.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Resync Local Data")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(state == .offline ? .secondary : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            // ambient-allow: a control, not a container.
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                }

                SettingsLabRow(title: "Metrics",
                               detail: "Live counters and latency for this device's sync activity",
                               symbol: "chart.bar.xaxis")
            }

            Text("KEPT WORD FOR WORD: the two resync footers, the confirmation body (\"Deletes all cached galleries, subjects, and images on this device, then re-downloads them. Any pending uploads … will be lost. Stay on Wi-Fi until status returns to Synced.\") and its destructive \"Clear & Resync\". This is the ONE screen in the tree that understands the device can be offline, and that understanding is kept exactly.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            // 3 — logout.
            VStack(alignment: .leading, spacing: 8) {
                Text("Log out")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    // ambient-allow: a destructive control, not a container.
                    .background(Capsule().fill(Color.red.opacity(0.12)))

                Text("PROPOSED — a destructive role and a confirmation on log out, and an error surface when it fails. Today it is a plain row with none of the three: the failure is swallowed to a `print`, so a sign-out that did not happen looks exactly like one that did, and the local PII purge that goes with it never runs.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("PROPOSED — tab-bar clearance. Settings and every screen it pushes (except PTO Balance, which insets itself) have none, so this button sits UNDER the floating tab bar today. A safe-area inset only insets the view it is applied to; it does not travel into a pushed screen.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("NOT IN THIS TREE, and not added: notification preferences. The inventory enumerates all 14 Settings files and there is no notifications screen among them — push behaviour is server-side and has no client control. A settings mockup that drew one would be promising a screen that has never existed.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Account info

private struct SettingsLabAccount: View {
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Lab · edit mode", isOn: $editing)
                .font(.caption)
                .tint(SettingsMockup.featureTint)

            AmbientFormSection(title: "Personal information",
                               status: editing ? "editing" : "Maria Alvarez",
                               statusTint: editing ? .orange : nil) {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsLabField(label: "First Name", value: "Maria", editing: editing)
                    SettingsLabField(label: "Last Name", value: "Alvarez", editing: editing)
                    SettingsLabField(label: "Display Name", value: "Maria A.", editing: editing)
                    SettingsLabField(label: "Phone", value: "(555) 010-4477", editing: editing)
                    Divider()
                    SettingsLabStatLine(label: "Email", value: "maria@iconikphoto.com")
                    Text("Email is READ-ONLY here. It is editable today and writes `users.email` — but Supabase Auth's email is never changed, so the two diverge and sign-in still needs the old address. Changing an account's email is an auth operation, not a profile edit, and it is out of scope for a design phase.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AmbientFormSection(title: "Address",
                               status: editing ? "editing" : "set",
                               statusTint: editing ? .orange : nil) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("48 Alder St, Springfield").font(.subheadline)
                    Text(editing
                         ? "In edit mode the address autocomplete and a draggable map replace the row."
                         : "\"Show Map\" opens a read-only map with hit testing off — unchanged.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("NAMED, NOT FIXED: city, state and zip are SAVED but have no field in either mode — only the autocomplete can set them, so a free-form address leaves them stale. And three different address autocompletes exist across this one directory (MapKit's completer, a Google Places service, and the shared component).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AmbientFormSection(title: "Professional",
                               status: "Photographer 1",
                               statusTint: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsLabField(label: "Position", value: "Photographer 1", editing: editing)
                    SettingsLabStatLine(label: "Role", value: "employee")
                    SettingsLabStatLine(label: "Mileage rate", value: Formatters.currency(0.67) + " / mile")
                    SettingsLabStatLine(label: "Organization", value: "Iconik School Photography")
                    Text("Role, organization and mileage rate STAY VISIBLE in edit mode. Today entering Edit removes all three with no substitute, so the one screen that tells a photographer their mileage rate hides it the moment they touch anything.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The raw organization UUID is replaced by the organization's NAME. The uuid was on screen for support; it is not something a photographer can use, and the name identifies the same thing.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Empty values still read \"Not set\" in orange — kept. NAMED, NOT FIXED (a service-layer defect, out of scope for D12): the background profile refresh lands AFTER the form is seeded and nothing re-seeds it, so Edit can save stale values over fresher server data.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Profile photo

private struct SettingsLabPhoto: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 12) {
                AmbientAvatar(name: "Maria Alvarez", size: 120)
                Text("Select New Photo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    // ambient-allow: the primary action — a control.
                    .background(Capsule().fill(SettingsMockup.featureTint))
            }
            .frame(maxWidth: .infinity)
            .ambientCard(density: .roomy, fillWidth: true, contentAlignment: .center)

            Text("This screen gets a nav title. Today it sets none, so it inherits a blank bar and prints \"Profile Photo\" into its own content instead.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("NOT PROMISED: cropping, removing the photo, or a cancel once an image is chosen. None of the three exists and each is a feature. PROPOSED — a photo-library permission check: there is none today, so a user who denied access gets an empty picker with no explanation.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("NAMED, NOT FIXED: the upload writes to a FIXED path with `upsert: true` and stores a public URL, so the URL never changes and a replaced photo can serve from cache indefinitely.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - School info list

private struct SettingsLabSchools: View {
    let state: SettingsLabState
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsLabSearchField(placeholder: "Search schools", text: $query)

            switch state {
            case .loading:
                SettingsLabLoading(message: "Loading schools…")
            case .failed:
                SettingsLabFailure(
                    message: "Couldn't load schools.",
                    detail: "PROPOSED — a retry and a distinct failure state. Today a failed load raises an alert titled \"Error\" and leaves the screen showing nothing, which is the same picture as an organization with no schools.")
            case .offline:
                SettingsLabFailure(
                    message: "You're offline — showing the last list this device downloaded.",
                    detail: "PROPOSED — offline is understood by exactly ONE file in this tree (the root Settings screen). Nothing else in Settings knows the device can be offline.")
            case .ready:
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(DesignLabSampleData.schoolsInfo) { school in
                        SettingsLabSchoolRow(school: school)
                    }
                    Text("Search is ADDED. There is no search, filter, sort or grouping anywhere in the 14 Settings files; the list is alphabetical from the service and that is the whole of it. On an organization with a hundred schools that is a long scroll to reach one address.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("\"Mileage: --\" is replaced by a stated reason. Today `--` is drawn both for a genuine zero AND for a per-school query that failed, and the two are indistinguishable. NAMED, NOT FIXED: those per-school figures are an N+1 fan-out — one report query per school — and the mileage comparison uses a full ISO timestamp here against a bare date in the service.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("KEPT: the empty state's \"No schools found\" and its \"Add Your First School\" button, the toolbar \"Add School\", and the Add School sheet's verify-then-drag-the-pin flow. PROPOSED there — Save is gated on having verified the address and says WHY, because today it is simply grey with no explanation.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("NAMED, NOT FIXED: deactivated schools are listed, because the service never filters `is_active`.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsLabSchoolRow: View {
    let school: LabSchoolInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(school.name).font(AmbientDensity.compact.titleFont).lineLimit(2)
                Spacer(minLength: 8)
                if let miles = school.seasonMiles {
                    Text(String(format: "%.1f mi", miles))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SettingsMockup.featureTint)
                } else {
                    AmbientBadge(text: "no mileage yet", tint: .secondary)
                }
            }
            Text(school.address).font(.caption).foregroundStyle(.secondary)
            if school.coordinates == nil {
                Text("Not geocoded — no map, and coordinates cannot be edited from this app.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

// MARK: - School detail

private struct SettingsLabSchoolDetail: View {
    let state: SettingsLabState
    private var school: LabSchoolInfo { DesignLabSampleData.schoolsInfo[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state == .loading {
                SettingsLabLoading(message: "Loading school…")
                Text("PROPOSED — a loading state. Today the form renders immediately with an EMPTY name, an empty address and 0.0 miles until the fetch lands, so a school with no data and a school still loading look identical.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // 5 — the screen is about a school, and says which.
                VStack(alignment: .leading, spacing: 3) {
                    Text(school.name).font(.system(size: 22, weight: .semibold))
                    Text(school.address).font(.subheadline).foregroundStyle(.secondary)
                }
                .ambientCard(density: .roomy, fillWidth: true)

                Text("The title is the SCHOOL'S NAME. Today the bar says \"School Detail\" on every school in the org.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                AmbientFormSection(title: "Season mileage",
                                   status: "Jul 15 – Jun 1",
                                   statusTint: nil) {
                    VStack(alignment: .leading, spacing: 6) {
                        SettingsLabStatLine(label: "Total miles driven",
                                            value: String(format: "%.1f miles", school.seasonMiles ?? 0))
                        SettingsLabStatLine(label: "Daily job reports this season",
                                            value: "\(school.reportCount)")
                    }
                }

                AmbientFormSection(title: "Location photos",
                                   status: school.photoLabels.isEmpty ? "none" : "\(school.photoLabels.count)",
                                   statusTint: school.photoLabels.isEmpty ? nil : .blue) {
                    VStack(alignment: .leading, spacing: 8) {
                        if school.photoLabels.isEmpty {
                            Text("No photos attached.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(school.photoLabels, id: \.self) { label in
                                HStack {
                                    Image(systemName: "photo").foregroundStyle(.secondary)
                                    Text(label).font(.subheadline)
                                    Spacer(minLength: 0)
                                    Image(systemName: "trash").foregroundStyle(.red)
                                }
                            }
                        }
                        Text("PROPOSED — a confirmation before deleting a location photo. Today there is none, the row is removed from the screen BEFORE the write, so a failed delete leaves the photo gone from the UI and still in the database with no restore — and the storage object is never deleted either, so files accumulate.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("NAMED, NOT FIXED: each photo's URL is a SIGNED url with a one-year expiry, persisted into the database — every location photo silently stops loading exactly one year after it was uploaded.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                renameWarning

                Text("KEPT: the read-only report rows and the \"Report Details\" screen behind them — date, photographer, school, mileage, job notes, job descriptions, extra items, cards scanned, job box/camera cards, sports background shot, attached photos. It has no edit, no delete and no share, and none is added.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 5 — the warning, and the reason it has to exist.
    private var renameWarning: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientNoteCard(
                title: "Renaming a school",
                text: "Reports are matched to a school by its NAME. Renaming this school hides every daily job report and every mileage figure already filed under the old name.",
                accent: .orange, density: .compact)
            Text("PROPOSED — this warning, and the rename staying behind an explicit Save rather than firing per keystroke. Today the school's mileage and report queries key off the LIVE editable field, so typing re-queries the half-typed name; the rename itself is offered with no warning and no migration.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Metrics

private struct SettingsLabMetrics: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientNoteCard(
                title: "What this measures",
                text: "Sync activity on THIS device only — commands, acknowledgements, disconnects and image fetches, counted since the app launched. Nothing here is about jobs, mileage or payroll.",
                accent: SettingsMockup.featureTint, density: .compact)

            AmbientFormSection(title: "Counters", status: "since launch", statusTint: nil) {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsLabStatLine(label: "sync.command.sent", value: "1,204")
                    SettingsLabStatLine(label: "sync.command.acked", value: "1,201")
                    SettingsLabStatLine(label: "sync.disconnect", value: "3")
                }
            }

            AmbientFormSection(title: "Latency", status: "p50 / p95 / p99", statusTint: nil) {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsLabStatLine(label: "thumbnail.fetch", value: "42 / 180 / 460 ms")
                    SettingsLabStatLine(label: "image.fetch", value: "310 / 980 / 2,400 ms")
                }
            }

            Text("The counter caption is corrected. It claims \"since the module loaded\" today, but the buffer holds 5,000 samples and silently drops the oldest, so on a busy day the number is \"since the buffer rolled\".")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Export stays, exporting TODAY'S file only — and it now says when there is nothing to export. Today it hands the share sheet a path whether or not the file exists, with no message. NOT PROMISED: a multi-day picker. The function that lists past files has zero call sites, and its own doc comment promises a picker that does not exist.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Auth

private struct SettingsLabAuth: View {
    @State private var screen: SettingsLabAuthScreen = .signIn
    @State private var failedProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Screen", selection: $screen) {
                ForEach(SettingsLabAuthScreen.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch screen {
            case .signIn: signIn
            case .create: createAccount
            case .forgot: forgot
            case .reset: reset
            }
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientFormSection(title: "Sign in", status: "", statusTint: nil) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Email", text: .constant("")).font(.subheadline)
                    Divider()
                    SecureField("Password", text: .constant("")).font(.subheadline)
                    Text("Forgot password?")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SettingsMockup.featureTint)
                }
            }

            Text("Sign In")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                // ambient-allow: the primary action — a control.
                .background(Capsule().fill(SettingsMockup.featureTint))

            Toggle("Lab · the profile fetch fails", isOn: $failedProfile)
                .font(.caption)
                .tint(.red)

            if failedProfile {
                AmbientNoteCard(
                    title: "Couldn't load your profile",
                    text: "You are signed in, but we couldn't read your organization or your permissions. Try again — signing in without them leaves every screen empty.",
                    accent: .red, density: .compact)
                Text("PROPOSED, and it is the highest-severity finding in this half of the batch: today sign-in PROCEEDS when the profile fetch fails. The user lands in the app with an EMPTY organization id, a role defaulted to \"employee\" and NO permissions loaded, after which every org-scoped screen guards out to blank — which reads as an app with no data rather than a failed sign-in. Drawing this state is a design proposal; making it happen is a code change and is not approved by approving this screen.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("KEPT: \"Don't have an account? Create one.\" and the nine mapped user-facing error messages this screen already routes through — it is the ONLY auth screen that does. That mapper becomes the error treatment on all four.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var createAccount: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientFormSection(title: "Create account", status: "6 fields", statusTint: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["Organization ID", "First Name", "Last Name", "Email"], id: \.self) { label in
                        Text(label).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Password · at least 6 characters").font(.subheadline)
                    Text("Confirm Password").font(.subheadline)
                }
            }

            Text("The password rules are SHOWN as a live checklist, the same one the reset screen already has. Today Create Account shows no rules and enforces no minimum client-side while Reset Password shows a 6-character checklist — two screens setting the same password to two different standards.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("PROPOSED — errors here go through the same user-facing mapper as sign-in. Today they are raw `localizedDescription`, so a duplicate key or an RLS violation prints Postgrest text on screen. And on success the screen NAVIGATES: today it shows a green \"Account created successfully. Please sign in.\" and stays put with the form still filled in, password and all.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("NOT PROPOSED, and it needs a decision elsewhere: this screen inserts the user row with a USER-TYPED organization id and a client-supplied role, with no check that the organization exists and no membership check. A partial signup also orphans an auth user with no profile row, which then fails forever with \"already exists\" — a person who half-signed-up can never retry. Both are server-side concerns; nothing in this design fixes them and nothing in this design should be read as fixing them.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var forgot: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientFormSection(title: "Reset password", status: "", statusTint: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.subheadline)
                    TextField("Email", text: .constant("")).font(.subheadline)
                }
            }
            AmbientNoteCard(
                title: "Check Your Email",
                text: "If an account exists with maria@iconikphoto.com, you will receive a password reset link shortly. Click the link in the email to reset your password.",
                accent: .green, density: .compact)
            Text("KEPT EXACTLY, including the deliberate enumeration-safe wording. NAMED, NOT FIXED: this screen sets \"sent\" on BOTH branches, so its error state is unreachable — the success view replaces the form whether the request succeeded or not. That is a code path, not a layout; the four error strings its own documentation promises do not exist in the code at all.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reset: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientFormSection(title: "Set a new password", status: "2 rules", statusTint: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Password").font(.subheadline)
                    Text("Confirm Password").font(.subheadline)
                    Divider()
                    Label("At least 6 characters", systemImage: "circle").font(.caption)
                    Label("Passwords match", systemImage: "circle").font(.caption)
                }
            }

            AmbientNoteCard(
                title: "This link has expired",
                text: "Password reset links can only be used once, and they expire. Request a new one from the sign-in screen.",
                accent: .orange, density: .compact)

            Text("PROPOSED — the invalid/expired link state. `IOS_PASSWORD_RESET_FLOW.md` documents it and it DOES NOT EXIST: when the link fails, the error is set but the sheet is never presented, so the user taps a bad link and sees ABSOLUTELY NOTHING happen. That silent failure is the reason this state is drawn.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("KEPT: the live rule checklist, the success view, and signing the user out after a password change. The doc's \"Back to Login\" link does not exist and is not added — the toolbar action is \"Cancel\" and \"Sign In\" appears only in the success view.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Appearance

private struct SettingsLabAppearance: View {
    @State private var theme = "system"

    private let options: [(id: String, label: String, symbol: String)] = [
        ("system", "System", "gear"),
        ("light", "Light", "sun.max"),
        ("dark", "Dark", "moon")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                ForEach(options, id: \.id) { option in
                    Button {
                        withAnimation(AmbientMotion.snappy) { theme = option.id }
                        AmbientHaptics.selection()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.symbol)
                                .foregroundStyle(theme == option.id ? SettingsMockup.featureTint : .secondary)
                                .frame(width: 22)
                            Text(option.label).font(.subheadline)
                            Spacer(minLength: 0)
                            if theme == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SettingsMockup.featureTint)
                            }
                        }
                        .ambientCard(density: .compact, fillWidth: true)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Unchanged in behaviour: the choice commits the instant a row is tapped and there is no Cancel. What changes is that this is a SCREEN inside Settings rather than a bare untokenised List in a sheet off the hamburger, and the checkmark is tinted rather than a bare system glyph.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("NAMED, NOT FIXED: the theme is applied by overriding the interface style on every window of `connectedScenes.first`, which is unordered — on an iPad with two windows this can apply to a scene other than the visible one. The same function also writes an \"AppleInterfaceStyle\" string into UserDefaults and posts a system-looking notification; NOTHING in the app reads either. Both statements are dead code, and this design does not carry them forward.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Components

private struct SettingsLabRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(SettingsMockup.featureTint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AmbientDensity.compact.titleFont)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

private struct SettingsLabField: View {
    let label: String
    let value: String
    let editing: Bool

    var body: some View {
        if editing {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField(label, text: .constant(value)).font(.subheadline)
            }
        } else {
            SettingsLabStatLine(label: label, value: value)
        }
    }
}

private struct SettingsLabStatLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.footnote.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }
}

private struct SettingsLabSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text).font(.subheadline)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .ambientCard(density: .compact, fill: .surface,
                     border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
    }
}

private struct SettingsLabLoading: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .ambientCard(density: .roomy, fillWidth: true, contentAlignment: .center)
    }
}

private struct SettingsLabFailure: View {
    let message: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button {} label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        // ambient-allow: a retry control, not a container.
                        .background(Capsule().fill(Color.orange))
                }
                .buttonStyle(.plain)
            }
            .ambientCard(density: .compact, fillWidth: true)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
