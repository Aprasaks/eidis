import SwiftUI

// MARK: 기획서 데이터 (Mac JarvisPlanRemote.swift 의 "planDocs" 응답)

struct JARVISPlanDoc: Decodable, Identifiable, Hashable {
    let file: String
    let title: String
    let updatedAt: String
    let markdown: String
    let truncated: Bool?
    var id: String { file }

    var updatedLabel: String {
        guard let date = ISO8601DateFormatter().date(from: updatedAt) else { return "" }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
}

struct JARVISPlanDocsReply: Decodable {
    let docs: [JARVISPlanDoc]
}

// MARK: 주식 데이터 (Mac JarvisStockBoard.phoneSnapshot 의 "stockSnapshot" 응답)

struct JARVISStockRow: Decodable, Identifiable {
    let rank: Int
    let symbol: String
    let name: String
    let price: String
    let changeRate: String
    let currency: String
    var id: String { symbol }

    var priceLabel: String {
        guard let value = Double(price) else { return price }
        return currency == "KRW" ? value.formatted(.number.precision(.fractionLength(0))) + "원"
                                 : "$" + value.formatted(.number.precision(.fractionLength(2)))
    }
    /// 등락률: 토스증권은 비율로 준다 (0.012 = +1.2%, 맥 주식 화면과 같은 계산)
    var change: Double? { Double(changeRate).map { rate in rate * 100 } }
}

struct JARVISStockMarket: Decodable, Identifiable {
    let market: String
    let rankedAt: String
    let rows: [JARVISStockRow]
    var id: String { market }
    var title: String { market == "KR" ? "국내" : "미국" }
}

struct JARVISStockSnapshot: Decodable {
    let checkedAt: String?
    let metric: String?
    let markets: [JARVISStockMarket]?
    let problem: String?

    var checkedLabel: String {
        guard let checkedAt, let date = ISO8601DateFormatter().date(from: checkedAt) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: 기억 탭 = 프로젝트 기획서 + 주식

struct JARVISMemoryTabView: View {
    enum Section: String, CaseIterable, Identifiable {
        case plans = "기획서", stocks = "주식"
        var id: String { rawValue }
    }

    @ObservedObject var calendar: JARVISCalendarStore
    @ObservedObject var nearby: JARVISMobileNearbyCalendar
    @State private var section: Section = .plans
    @State private var openDoc: JARVISPlanDoc?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("기억")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-1.2)
                .padding(.top, 25)

            Picker("기억 항목", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch section {
            case .plans: plans
            case .stocks: stocks
            }
        }
        .sheet(item: $openDoc) { JARVISPlanDocView(doc: $0) }
        .task { if nearby.planDocs.isEmpty { nearby.refreshPlans() } }
        .onChange(of: section) { _, now in if now == .stocks { nearby.refreshStocks() } }
    }

    private var stocks: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(nearby.stockStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(JARVISPalette.muted)
                    .lineLimit(2)
                Spacer()
                Button { nearby.refreshStocks() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13))
                }
                .disabled(nearby.stockLoading)
                .accessibilityLabel("주식 새로고침")
            }
            ForEach(nearby.stockSnapshot?.markets ?? []) { market in
                VStack(alignment: .leading, spacing: 0) {
                    Text(market.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(JARVISPalette.gold)
                        .padding(.bottom, 6)
                    ForEach(market.rows) { row in
                        HStack(spacing: 10) {
                            Text("\(row.rank)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(JARVISPalette.muted)
                                .frame(width: 20, alignment: .trailing)
                            Text(row.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(row.priceLabel)
                                .font(.system(size: 12, design: .monospaced))
                            if let change = row.change {
                                Text(String(format: "%+.2f%%", change))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(change > 0 ? Color(red: 0.95, green: 0.36, blue: 0.33)
                                                     : change < 0 ? Color(red: 0.36, green: 0.58, blue: 0.98) : JARVISPalette.muted)
                                    .frame(width: 66, alignment: .trailing)
                            }
                        }
                        .padding(.vertical, 7)
                        Divider().overlay(JARVISPalette.panelEdge)
                    }
                }
                .padding(14)
                .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(JARVISPalette.panelEdge, lineWidth: 0.75))
            }
        }
        .onAppear { if nearby.stockSnapshot == nil { nearby.refreshStocks() } }
    }

    private var plans: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(nearby.planStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(JARVISPalette.muted)
                Spacer()
                Button { nearby.refreshPlans() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13))
                }
                .disabled(nearby.planLoading)
                .accessibilityLabel("기획서 새로고침")
            }
            ForEach(nearby.planDocs) { doc in
                Button { openDoc = doc } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(JARVISPalette.gold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(doc.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(JARVISPalette.white)
                                .multilineTextAlignment(.leading)
                            Text("수정 \(doc.updatedLabel)")
                                .font(.system(size: 10))
                                .foregroundStyle(JARVISPalette.muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(JARVISPalette.muted)
                    }
                    .padding(14)
                    .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(JARVISPalette.panelEdge, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 기획서 읽기 화면. 마크다운의 제목·목록·표·코드 블록을 줄 단위로 가볍게 그린다.
struct JARVISPlanDocView: View {
    let doc: JARVISPlanDoc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in row(line) }
                    if doc.truncated == true {
                        Text("문서가 길어서 앞부분만 받았어요. 전체는 맥에서 확인하세요.")
                            .font(.system(size: 11))
                            .foregroundStyle(JARVISPalette.muted)
                            .padding(.top, 12)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(JARVISPalette.black)
            .navigationTitle("기획서")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private var lines: [String] {
        doc.markdown.components(separatedBy: "\n").filter { !$0.hasPrefix("```") }
    }

    private func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
    }

    @ViewBuilder private func row(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            Color.clear.frame(height: 4)
        } else if line.hasPrefix("# ") {
            inline(String(line.dropFirst(2))).font(.system(size: 22, weight: .bold)).padding(.top, 6)
        } else if line.hasPrefix("## ") {
            inline(String(line.dropFirst(3))).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(JARVISPalette.gold).padding(.top, 14)
        } else if line.hasPrefix("### ") {
            inline(String(line.dropFirst(4))).font(.system(size: 15, weight: .semibold)).padding(.top, 8)
        } else if line.hasPrefix("|") {
            if !line.contains("---") {
                Text(line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                        .replacingOccurrences(of: "|", with: " · ")
                        .replacingOccurrences(of: "**", with: ""))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(JARVISPalette.white.opacity(0.85))
            }
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•").foregroundStyle(JARVISPalette.gold)
                inline(String(line.dropFirst(2))).font(.system(size: 14))
            }
            .padding(.leading, raw.hasPrefix("  ") ? 16 : 0)
        } else if line.hasPrefix(">") {
            inline(String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces))
                .font(.system(size: 13)).italic().foregroundStyle(JARVISPalette.muted)
        } else {
            inline(line).font(.system(size: 14))
        }
    }
}
