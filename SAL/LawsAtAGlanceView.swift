import SwiftUI

/// Quick topics for the selected state. Each one hands a question to SAL in the Chat tab.
struct LawsAtAGlanceView: View {
    let state: USState
    let onAsk: (String) -> Void

    private struct Topic: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let summary: String
        let question: String
    }

    private var topics: [Topic] {
        [
            Topic(title: "Traffic Stops", systemImage: "light.beacon.max",
                  summary: "What to do and what you have to share when you’re pulled over.",
                  question: "What are my rights during a traffic stop in \(state.name), and what do I have to provide?"),
            Topic(title: "Vehicle Searches", systemImage: "magnifyingglass",
                  summary: "When an officer can search your car, and how to decline politely.",
                  question: "When can police search my car in \(state.name), and can I refuse?"),
            Topic(title: "Speed Limits", systemImage: "gauge.with.dots.needle.67percent",
                  summary: "Default limits, work zones, and how speeding tickets work.",
                  question: "How do speed limits and speeding tickets work in \(state.name)?"),
            Topic(title: "Impaired Driving", systemImage: "wineglass",
                  summary: "Legal limits, testing, and what happens if you refuse a test.",
                  question: "What are the impaired driving laws in \(state.name), including breath test refusals?"),
            Topic(title: "Phones & Distraction", systemImage: "iphone.slash",
                  summary: "Rules on handheld phones, texting, and hands-free use.",
                  question: "What are the rules for using a phone while driving in \(state.name)?"),
            Topic(title: "Seat Belts & Child Seats", systemImage: "figure.seated.seatbelt",
                  summary: "Who has to buckle up and car seat requirements for kids.",
                  question: "What are the seat belt and child car seat laws in \(state.name)?"),
            Topic(title: "Insurance & Registration", systemImage: "doc.text",
                  summary: "Documents you need to carry and what happens without them.",
                  question: "What insurance and registration documents do I need to carry while driving in \(state.name)?"),
            Topic(title: "Accidents", systemImage: "car.side.rear.and.collision.and.car.side.front",
                  summary: "What you’re required to do after a crash.",
                  question: "What am I legally required to do after a car accident in \(state.name)?")
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(topics) { topic in
                        Button {
                            onAsk(topic.question)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: topic.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(Color(red: 0, green: 0.31, blue: 1))
                                    .frame(width: 32)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(topic.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(topic.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "bubble.left.and.text.bubble.right")
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityHint("Asks SAL about this topic in Chat.")
                    }
                } header: {
                    Text("\(state.name) topics")
                } footer: {
                    Text("Tap a topic to ask SAL. SAL gives general information, not legal advice.")
                }
            }
            .navigationTitle("Laws At A Glance")
        }
    }
}

#Preview {
    LawsAtAGlanceView(state: .michigan, onAsk: { _ in })
}
