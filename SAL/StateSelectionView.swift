import SwiftUI

struct StateSelectionView: View {
    let suggestedState: USState?
    let message: String
    let onConfirm: (USState) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedState: USState

    init(suggestedState: USState?, message: String, onConfirm: @escaping (USState) -> Void) {
        self.suggestedState = suggestedState
        self.message = message
        self.onConfirm = onConfirm
        _selectedState = State(initialValue: suggestedState ?? .michigan)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(message, systemImage: "location.circle")
                        .fixedSize(horizontal: false, vertical: true)
                    Picker("State", selection: $selectedState) {
                        ForEach(USState.sorted) { state in
                            Text(state.name).tag(state)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("Approximate location is enough. SAL saves your selected state on this device, not your coordinates.")
                }

                Section {
                    Text("Michigan is the first state available in SAL.")
                    if selectedState != .michigan {
                        Text("\(selectedState.name) is not supported yet. You can choose Michigan to explore its laws.")
                            .foregroundStyle(.secondary)
                        Button("Choose Michigan") { selectedState = .michigan }
                    }
                }

                Section {
                    Button {
                        onConfirm(selectedState)
                    } label: {
                        Text("Continue with \(selectedState.name)")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .disabled(selectedState != .michigan)
                }
            }
            .navigationTitle("Confirm your state")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
