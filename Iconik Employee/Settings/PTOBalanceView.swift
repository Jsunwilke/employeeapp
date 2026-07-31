//  PTOBalanceView.swift
//  Iconik Employee — the PTO balance, converted to Ambient in AMB.8
//
//  KEPT WHOLE. Every row, the accrual policy card and the projection survive; the
//  screen simply gains a second, obvious route in from the surface it is about
//  (My Time Off), while Settings keeps the route it always had.
//
//  THREE THINGS FIXED HERE BECAUSE THE REDESIGN MADE THEM UNAVOIDABLE:
//
//    1. THE SIGN WAS DROPPED FROM NEGATIVE NUMBERS. `BalanceRow` printed
//       `value < 0 ? "" : "+"`, so every non-negative row got a leading "+" and
//       negatives got NOTHING. "Pending Requests" is passed `-pendingBalance`, so
//       8 hours of pending time off rendered as "8" — visually identical to a
//       credit, on the one row that is a debit.
//    2. EVERY BALANCE FIGURE WAS `Int(...)`-TRUNCATED, so a 4.5-hour balance read
//       "4". The breakdown and the hero are `%.1f` now. The one surviving stat
//       tile is still a rounded integer, because `AmbientStatTile` takes an Int —
//       it is labelled "(hours)" so the unit is not lost with the decimal.
//    3. IT IS A PUSHED SCREEN WITH NO TAB-BAR CLEARANCE. The rule written into
//       BottomTabBar.swift is that an inset does not travel out of a navigation
//       container into what that container pushes — so the last row sat under the
//       floating bar, from Settings then and from both routes now. It insets
//       itself.
//
//  ⚠️ THE "USED THIS YEAR" TILE IS REMOVED. It is not shown at all — see the note
//  on `yearToDate` below for why swapping it to the real column made it worse.
//  Restoring it needs a data-layer change and belongs to TOF.1.
//
//  (This header previously claimed the tile "now shows balance.used". It did, for
//  one commit, and then the data audit showed nothing maintains that column
//  either. Left uncorrected it would have been a file header stating something
//  untrue of the code beneath it — the exact shape of the AMB.7 commit that said
//  a clear landed "in both early returns" when it had not.)

import SwiftUI

struct PTOBalanceView: View {
    /// A pushed screen has to inset itself past the floating tab bar. Both routes
    /// in (Settings, and now My Time Off) push into a container that sits under
    /// the bar, so this defaults to true and covers both.
    var isPushed: Bool = true

    private let ptoService = PTOService.shared

    @State private var balance: PTOBalance?
    @State private var settings: PTOSettings?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var projectedDate = Date().addingTimeInterval(30 * 24 * 60 * 60)
    @State private var projectedBalance = 0.0

    private var tint: Color { TimeOffStyle.requests }

    private var userId: String? { UserManager.shared.getCurrentUserIDUnified() }
    private var organizationId: String? { UserDefaults.standard.string(forKey: "userOrganizationID") }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isLoading {
                        loadingState
                    } else if !errorMessage.isEmpty {
                        errorState
                    } else if let balance {
                        hero(balance)
                        breakdown(balance)
                        yearToDate(balance)
                        accrualPolicy
                        projection(balance)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .modifier(PTOBalanceClearance(active: isPushed))
        .navigationTitle("PTO Balance")
        // Inline, as the mockup specified and as every pushed AMB.7 screen does.
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadPTOData)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading PTO information...").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var errorState: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Couldn't load your balance").font(.headline)
            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: loadPTOData) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    // ambient-allow: a control, not a card.
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Content

    private func hero(_ balance: PTOBalance) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // One decimal, not Int(). A half-hour of PTO is a real half-hour.
            Text("\(balance.availableBalance, specifier: "%.1f")")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text("hours available")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .ambientCard(density: .hero, state: .highlighted, glow: tint, fillWidth: true)
    }

    private func breakdown(_ balance: PTOBalance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Breakdown")
            VStack(spacing: 0) {
                TimeOffSignedRow(label: "Total Balance", value: balance.balance, tint: .primary)
                // Conditional on being greater than zero, as today.
                if balance.pendingBalance > 0 {
                    Divider()
                    TimeOffSignedRow(label: "Pending Requests",
                                     value: -balance.pendingBalance,
                                     tint: .orange)
                }
                Divider()
                TimeOffSignedRow(label: "Available to Use",
                                 value: balance.availableBalance,
                                 tint: .green,
                                 emphasised: true)
                // Conditional on existing at all.
                if balance.bankingBalance > 0 {
                    Divider()
                    TimeOffSignedRow(label: "Banking Balance",
                                     value: balance.bankingBalance,
                                     tint: .blue)
                }
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
    }

    /// THE "USED THIS YEAR" TILE IS GONE, and removing it is the point.
    ///
    /// The old screen rendered `usedThisYear`, which is declared OUTSIDE
    /// `CodingKeys` and therefore always decoded as 0 — it displayed a hardcoded
    /// zero. My first fix pointed it at `balance.used`, the real column. The data
    /// audit then established that NOTHING MAINTAINS THAT COLUMN either:
    /// `PTOService.usePTOHours` writes only `balance`, `pending_balance` and
    /// `updated_at`, so `useHours()` increments `used` in memory and drops it; and
    /// the web app never reads or writes it at all.
    ///
    /// So the "fix" swapped a wrong number for a differently wrong number that
    /// LOOKS authoritative. On a payroll screen that is worse. The tile is removed
    /// rather than shown, which is the same judgement the balance lead makes about
    /// a failed load. Making it real is a data-layer change — TOF.1.
    private func yearToDate(_ balance: PTOBalance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Year to date")
            AmbientStatTile(value: Int(balance.totalAccrued.rounded()),
                            label: "Total accrued (hours)",
                            systemImage: "plus.circle",
                            tint: .green)
            Text("Hours used this year are not tracked on this device — the figure the app stored was never written to the database. Payroll has the authoritative number.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Conditional on the org having accrual settings AND having enabled them —
    /// and enabled DEFAULTS TO FALSE, so for most orgs this card is simply absent.
    @ViewBuilder
    private var accrualPolicy: some View {
        if let settings, settings.enabled {
            VStack(alignment: .leading, spacing: 8) {
                AmbientSectionTitle("Accrual policy")
                VStack(spacing: 0) {
                    TimeOffDetailRow(label: "Accrual Rate", value: settings.formattedAccrualRate)
                    Divider()
                    TimeOffDetailRow(label: "Maximum Balance", value: settings.formattedMaxAccrual)
                    Divider()
                    TimeOffDetailRow(label: "Rollover Policy", value: settings.formattedRolloverPolicy)
                }
                .ambientCard(density: .compact, fillWidth: true)
                // Only true for an ACCRUAL org. A yearly-allotment org gets its
                // hours in a lump and `calculateProjectedAccrual` returns 0 for it,
                // so stating this unconditionally was an introduced false claim.
                if settings.usesAccrualSystem {
                    Text("Accrual counts business days only, Monday to Friday, at 8 hours a day.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func projection(_ balance: PTOBalance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Projection")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Calculate balance for").font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    DatePicker("", selection: $projectedDate,
                               in: Date()...,
                               displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: projectedDate) { _ in calculateProjectedBalance() }
                }
                Divider()
                HStack {
                    // LABELLED "total", because that is what it is.
                    // `calculateProjectedBalance` projects `totalBalance` — the raw
                    // column — while the hero above shows `availableBalance`
                    // (`balance - pending_balance`). Showing an unqualified
                    // "Projected balance" beneath an "available" hero invited the
                    // reader to compare two different quantities.
                    Text("Projected total balance").font(.subheadline)
                    Spacer(minLength: 8)
                    Text("\(projectedBalance, specifier: "%.1f") h")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                }
                // MEASURED FROM THE SAME BASE IT IS PROJECTED FROM.
                //
                // This line used to read `projectedBalance - availableBalance`,
                // subtracting an available-based figure from a total-based one to
                // manufacture an accrual. With any pending hours and a
                // non-accrual org the difference was exactly `pending_balance`, so
                // the screen asserted "You will accrue 8.0 more hours by this
                // date" for an organisation that has no accrual policy at all.
                // `projectedBalance - balance.balance` is like-for-like and IS the
                // accrual. The same mistake was removed from the request form one
                // commit earlier and left here, in a file that commit edited —
                // the instance, not the class.
                if projectedBalance > balance.balance {
                    Text("You will accrue \(projectedBalance - balance.balance, specifier: "%.1f") more hours by this date.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    // MARK: - Data

    private func loadPTOData() {
        guard let userId, !userId.isEmpty,
              let orgId = organizationId, !orgId.isEmpty else {
            errorMessage = "Unable to load user information"
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = ""

        Task {
            do {
                let loadedBalance = try await ptoService.getPTOBalance(userId: userId, organizationID: orgId)
                let loadedSettings = try await ptoService.getPTOSettings(organizationID: orgId)
                await MainActor.run {
                    self.balance = loadedBalance
                    self.settings = loadedSettings
                    self.calculateProjectedBalance()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load PTO data: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func calculateProjectedBalance() {
        guard let balance, let settings else { return }
        projectedBalance = ptoService.calculateProjectedBalance(
            currentBalance: balance,
            settings: settings,
            targetDate: projectedDate)
    }
}

/// A PUSHED screen insets itself. A safe-area inset does not travel out of a
/// navigation container into the screens that container pushes — the rule written
/// into BottomTabBar.swift after the app paid for it four times over.
private struct PTOBalanceClearance: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.tabBarClearance() } else { content }
    }
}
