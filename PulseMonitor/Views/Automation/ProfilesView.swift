import SwiftUI

/// Power profiles and the IF/THEN automation engine.
///
/// Profiles change how PulseMonitor itself behaves. They are explicit about not
/// touching OS power settings, because those writes need administrator rights
/// this process does not hold.
public struct ProfilesView: View {
    @Bindable var settings: AppSettings
    let profileService: PowerProfileService
    @Bindable var automation: AutomationEngine

    @State private var editingRule: AutomationRule?
    @State private var isCreatingRule = false

    public init(settings: AppSettings, profileService: PowerProfileService, automation: AutomationEngine) {
        self.settings = settings
        self.profileService = profileService
        self.automation = automation
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.gridSpacing) {
                profilesSection
                automationSection
            }
            .padding(DesignTokens.sectionSpacing)
        }
        .background(AmbientBackdrop())
        .navigationTitle("Profiles & Automation")
        .sheet(item: $editingRule) { rule in
            RuleEditor(rule: rule) { updated in
                automation.update(updated)
                editingRule = nil
            } onCancel: {
                editingRule = nil
            }
        }
        .sheet(isPresented: $isCreatingRule) {
            RuleEditor(rule: AutomationRule(name: "New rule", trigger: .cpuAbove, action: .notify)) { created in
                automation.add(created)
                isCreatingRule = false
            } onCancel: {
                isCreatingRule = false
            }
        }
    }

    // MARK: - Profiles

    private var profilesSection: some View {
        GlassSection(title: "Power Profiles", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(PowerProfile.all) { profile in
                        profileCard(profile)
                    }
                }

                Text("Profiles adjust PulseMonitor's sampling rate, graph length, alert thresholds, overlay and notifications. They do not change macOS power settings — that requires administrator rights, so the app does not claim to do it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } accessory: {
            if !profileService.matchesActiveProfile() {
                Text("Edited")
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                    .foregroundStyle(.orange)
                    .help("Settings have been changed since this profile was applied.")
            }
        }
    }

    private func profileCard(_ profile: PowerProfile) -> some View {
        let isActive = settings.activeProfile == profile.kind

        return Button {
            withAnimation(DesignTokens.Motion.standard) {
                profileService.apply(profile.kind)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: profile.kind.symbol)
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    Text(profile.kind.displayName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text(profile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(String(format: "%.1fs", profile.refreshInterval), systemImage: "timer")
                    Label("\(Int(profile.cpuAlertThreshold))%", systemImage: "cpu")
                    Label("\(Int(profile.temperatureAlertC))°", systemImage: "thermometer")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.compactCornerRadius, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: DesignTokens.compactCornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Automation

    private var automationSection: some View {
        GlassSection(title: "Automation", systemImage: "bolt.badge.clock") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Run automation rules", isOn: $settings.automationEnabled)
                    .toggleStyle(.switch)

                Text("Rules are checked once per sample. Each rule waits out its cooldown before firing again, and every firing is written to the event log.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                ForEach(automation.rules) { rule in
                    ruleRow(rule)
                }

                Button {
                    isCreatingRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .opacity(settings.automationEnabled ? 1 : 0.6)
        }
    }

    private func ruleRow(_ rule: AutomationRule) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { automation.setEnabled($0, for: rule) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!settings.automationEnabled)

            VStack(alignment: .leading, spacing: 1) {
                Text(rule.name).font(.callout)
                Text(rule.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            if let fired = automation.lastFired[rule.id] {
                Text(fired.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("Last fired")
            }

            Button {
                editingRule = rule
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)

            Button {
                automation.remove(rule)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 3)
    }
}

/// Sheet for creating or editing one rule.
private struct RuleEditor: View {
    @State var rule: AutomationRule
    let onSave: (AutomationRule) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Automation Rule").font(.title3.weight(.semibold))

            Form {
                TextField("Name", text: $rule.name)

                Picker("If", selection: $rule.trigger) {
                    ForEach(AutomationRule.Trigger.allCases) { trigger in
                        Text(trigger.displayName).tag(trigger)
                    }
                }
                .onChange(of: rule.trigger) { _, newValue in
                    rule.threshold = newValue.defaultThreshold
                }

                if rule.trigger.needsThreshold {
                    HStack {
                        TextField(
                            "Threshold",
                            value: $rule.threshold,
                            format: .number.precision(.fractionLength(0))
                        )
                        Text(rule.trigger.unit).foregroundStyle(.secondary)
                    }
                }

                Picker("Then", selection: $rule.action) {
                    ForEach(AutomationRule.Action.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }

                if rule.action.needsProfile {
                    Picker("Profile", selection: $rule.profile) {
                        ForEach(PowerProfile.Kind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                }

                HStack {
                    TextField(
                        "Cooldown",
                        value: $rule.cooldownSeconds,
                        format: .number.precision(.fractionLength(0))
                    )
                    Text("seconds").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Text(rule.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save") { onSave(rule) }
                    .buttonStyle(.borderedProminent)
                    .disabled(rule.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
