import SwiftUI
import UniformTypeIdentifiers

struct PlannerView: View {
    @Binding var record: ScanRecord
    var onChange: () -> Void
    @Environment(ScanStore.self) private var store
    @State private var chat = ChatState()
    @State private var input = ""
    @State private var sending = false
    @State private var undo: [[LayoutItem]] = []
    @State private var importing = false
    @State private var copied = false
    @State private var showSettings = false
    @State private var hasKey = ClaudeClient.apiKey != nil

    private let starters = [
        "Navrhni rozmístění nábytku pro ložnici s pracovním koutem.",
        "Kam dát gauč, televizi a jídelní stůl pro 4?",
        "Zkontroluj současné rozvržení a navrhni vylepšení.",
        "Kolik nábytku se sem vejde, aby zůstalo dost místa na pohyb?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !hasKey { keyBanner }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.turns.isEmpty { intro }
                        ForEach(chat.turns) { turn in bubble(turn).id(turn.id) }
                        if sending {
                            HStack { ProgressView(); Text("Claude přemýšlí…").foregroundStyle(.secondary) }.id("sending")
                        }
                    }
                    .padding()
                }
                .onChange(of: chat.turns.count) { withAnimation { proxy.scrollTo(chat.turns.last?.id, anchor: .bottom) } }
                .onChange(of: sending) { if sending { withAnimation { proxy.scrollTo("sending") } } }
            }
            inputBar
        }
        .onAppear {
            chat = store.loadChat(record.id)
            hasKey = ClaudeClient.apiKey != nil
            // Debug: `-aiTest "request"` sends one planning request on launch (Simulator checks).
            let a = ProcessInfo.processInfo.arguments
            if let i = a.firstIndex(of: "-aiTest"), i + 1 < a.count { send(a[i + 1]) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { UIPasteboard.general.string = PlanBrief.prompt(record, request: input); copied = true } label: {
                        Label("Kopírovat zadání pro Clauda", systemImage: "doc.on.doc")
                    }
                    Button { importing = true } label: { Label("Importovat rozvržení (JSON)", systemImage: "square.and.arrow.down") }
                    if !undo.isEmpty {
                        Button { record.layout = undo.removeLast(); onChange() } label: {
                            Label("Vrátit předchozí rozvržení", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button { showSettings = true } label: { Label("API klíč", systemImage: "key") }
                    Divider()
                    Button(role: .destructive) { chat = ChatState(); store.saveChat(chat, record.id) } label: {
                        Label("Nový rozhovor", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { res in
            if case .success(let url) = res { importLayout(url) }
        }
        .alert("Zkopírováno", isPresented: $copied) {
            Button("OK") {}
        } message: {
            Text("Vlož zadání do Claude (claude.ai nebo Claude Code). Výsledné JSON pole `layout` ulož jako soubor a nahraj přes Importovat rozvržení.")
        }
        .sheet(isPresented: $showSettings, onDismiss: { hasKey = ClaudeClient.apiKey != nil }) { SettingsView() }
    }

    private var keyBanner: some View {
        Button { showSettings = true } label: {
            Label("Pro plánování v aplikaci zadej API klíč Anthropic. Bez něj můžeš zadání zkopírovat do Clauda ručně.",
                  systemImage: "key.fill")
                .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10).background(Color.yellow.opacity(0.2))
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plánování s Claudem").font(.title3.bold())
            Text("Claude dostane změřený půdorys, jeho obrázek a \(record.photos.count) fotek z této místnosti. Navržené rozvržení se hned zobrazí v půdorysu i ve 3D, kde ho můžeš dál posouvat a otáčet.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(starters, id: \.self) { s in chip(s) }
        }
    }

    private func bubble(_ t: ChatTurn) -> some View {
        VStack(alignment: t.role == .user ? .trailing : .leading, spacing: 6) {
            Text(LocalizedStringKey(t.text))
                .padding(10)
                .background(t.role == .user ? Color.accentColor.opacity(0.15) : t.role == .error ? Color.red.opacity(0.15) : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
            if t.hasLayout {
                Label("Rozvržení použito v půdorysu", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
            }
            if t.id == chat.turns.last?.id {
                ForEach(t.suggestions, id: \.self) { chip($0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: t.role == .user ? .trailing : .leading)
    }

    private func chip(_ s: String) -> some View {
        Button { send(s) } label: {
            Text(s).font(.footnote).multilineTextAlignment(.leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.5)))
        }
        .disabled(sending || !hasKey)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom) {
            TextField("Co chceš naplánovat?", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
            Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                .disabled(sending || input.trimmingCharacters(in: .whitespaces).isEmpty || !hasKey)
        }
        .padding(10)
        .background(.bar)
    }

    private func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        chat.turns.append(ChatTurn(role: .user, text: text))
        sending = true
        let rec = record
        Task {
            do {
                let msg: JSONValue
                if chat.apiMessages.isEmpty {
                    let planImage = Exporter.planPNG(rec, width: 1200)
                    let photos = rec.photos.prefix(8).compactMap { store.image(rec, $0).flatMap { ClaudeClient.shrink($0) } }
                    msg = ClaudeClient.firstMessage(rec: rec, planImage: planImage, photos: photos, request: text)
                } else {
                    msg = ClaudeClient.nextMessage(rec: rec, request: text)
                }
                let messages = chat.apiMessages + [msg]
                let started = Date()
                let reply = try await ClaudeClient.send(messages: messages)
                print("AITEST ok \(Int(Date().timeIntervalSince(started)))s, layout: \(reply.layout?.count ?? -1) items, suggestions: \(reply.suggestions.count)")
                chat.apiMessages = messages + [reply.rawContent]
                if let layout = reply.layout {
                    undo.append(record.layout)
                    record.layout = layout
                    onChange()
                }
                chat.turns.append(ChatTurn(role: .assistant, text: reply.message, suggestions: reply.suggestions,
                                           hasLayout: reply.layout != nil))
            } catch {
                print("AITEST error:", error.localizedDescription)
                chat.turns.append(ChatTurn(role: .error, text: error.localizedDescription))
            }
            sending = false
            store.saveChat(chat, record.id)
        }
    }

    private func importLayout(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        var items = try? JSONDecoder().decode([LayoutItem].self, from: data)
        if items == nil, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let arr = obj["layout"],
           let d = try? JSONSerialization.data(withJSONObject: arr) {
            items = try? JSONDecoder().decode([LayoutItem].self, from: d)
        }
        guard let items else {
            chat.turns.append(ChatTurn(role: .error, text: "Soubor neobsahuje platné rozvržení."))
            return
        }
        undo.append(record.layout)
        record.layout = items
        onChange()
        chat.turns.append(ChatTurn(role: .assistant, text: "Importováno \(items.count) kusů nábytku ze souboru \(url.lastPathComponent).", hasLayout: true))
        store.saveChat(chat, record.id)
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = Keychain.get("anthropic_api_key") ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("API klíč Anthropic") } footer: {
                    Text("Uloží se jen v Klíčence tohoto iPhonu. Klíč vytvoříš na platform.claude.com → API Keys. Plánování používá model \(ClaudeClient.model); jeden návrh stojí obvykle několik korun.")
                }
                if !key.isEmpty {
                    Button("Smazat klíč", role: .destructive) { key = ""; Keychain.set("anthropic_api_key", nil) }
                }
            }
            .navigationTitle("Nastavení")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit") { Keychain.set("anthropic_api_key", key.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                }
            }
        }
    }
}
