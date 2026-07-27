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
//    2. EVERY FIGURE WAS `Int(...)`-TRUNCATED, so a 4.5-hour balance read "4".
//    3. IT IS A PUSHED SCREEN WITH NO TAB-BAR CLEARANCE. The rule written into
//       BottomTabBar.swift is that an inset does not travel out of a navigation
//       container into what that container pushes — so the last row sat under the
//       floating bar, from Settings then and from both routes now. It insets
//       itself.
//
//  ⚠️ RECORDED, NOT FIXED — "Used This Year" was STRUCTURALLY always zero.
//  `PTOBalance.usedThisYear` is declared OUTSIDE `CodingKeys`, so it is never
//  decoded, and only `useHours` increments it in memory; the old screen rendered
//  it anyway. This now shows `balance.used`, the column the database actually
//  holds. The deeper defect — `usePTOHours` never PERSISTS `used`, so the column
//  stays 0 too — is a data-layer change and belongs to TOF.1.

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
            AmbientBackdrop(tint: tint, intensity: 0.7)

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
        .navigationBarTitleDisplayMode(.large)
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

    private func yearToDate(_ balance: PTOBalance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Year to date")
            HStack(spacing: 10) {
                AmbientStatTile(value: Int(balance.used.rounded()),
                                label: "Used this year",
                                systemImage: "calendar.badge.minus",
                                tint: .orange)
                AmbientStatTile(value: Int(balance.totalAccrued.rounded()),
                                label: "Total accrued",
                                systemImage: "plus.circle",
                                tint: .green)
            }
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
                Text("Accrual counts business days only, Monday to Friday, at 8 hours a day.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
                    Text("Projected balance").font(.subheadline)
                    Spacer(minLength: 8)
                    Text("\(projectedBalance, specifier: "%.1f") h")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                }
                // The old screen hid this whole readout behind `projectedBalance > 0`,
                // so an employee with no balance saw a date picker with nothing
                // under it and no explanation. A zero projection is an answer.
                if projectedBalance > balance.availableBalance {
                    Text("You will accrue \(projectedBalance - balance.availableBalance, specifier: "%.1f") more hours by this date.")
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
