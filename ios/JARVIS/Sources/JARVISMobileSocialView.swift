import SwiftUI
import UIKit

// MARK: - 데이터 (Mac JarvisSocialRemote.snapshot 응답과 같은 모양)

struct JARVISSocialSnapshot: Decodable {
    let checkedAt: String
    let channels: [JARVISSocialChannel]
    let carousel: JARVISSocialCarousel?
}

struct JARVISSocialChannel: Decodable, Identifiable {
    let name: String
    let connected: Bool
    let handle: String?
    let followers: Int?
    let posts: Int?
    let error: String?
    var id: String { name }
}

struct JARVISSocialCarousel: Decodable {
    let runID: String
    let title: String
    let articleURL: String
    /// "review" = 검토 대기, "approved" = 승인됨(게시 대기)
    let status: String
    let createdAt: String
    let caption: String
    let slideCount: Int
    /// 긴 변 400px JPEG(base64). 메시지 크기 제한 때문에 slideCount보다 적을 수 있다.
    let previews: [String]
    /// 슬라이드 PNG + 캡션의 SHA-256. 승인할 때 그대로 돌려보내 "본 버전만" 승인되게 한다.
    let digest: String
    let visualChecked: Bool
    /// 게시 완료 시 Instagram 게시물 주소 (이전 Mac 빌드에서는 없음)
    let permalink: String?
}

// MARK: - 화면

/// 아이폰 SNS 화면: Mac 자비스가 만든 캐러셀을 미리 보고 승인/반려한다.
/// 승인은 Mac에 "게시 대기"로 기록될 뿐이며, 이 화면이 직접 게시하지는 않는다.
struct JARVISMobileSocialView: View {
    @ObservedObject var nearby: JARVISMobileNearbyCalendar
    @State private var confirming: Bool?          // true = 승인 확인, false = 반려 확인
    @State private var showFullCaption = false
    @State private var page = 0
    @State private var showingPairing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusRow
            if !nearby.remembered && !nearby.connected {
                // 안내 문구만 있던 자리에 등록 화면을 바로 여는 버튼.
                Button { showingPairing = true } label: {
                    Label("Mac 연결하기 · 12자리 코드", systemImage: "link")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(JARVISPalette.gold)
            }
            channelGrid
            if let carousel = nearby.socialSnapshot?.carousel {
                carouselCard(carousel)
            } else if nearby.socialSnapshot != nil {
                emptyCard
            }
        }
        .onAppear { nearby.refreshSocial() }
        .sheet(isPresented: $showingPairing, onDismiss: { nearby.refreshSocial() }) {
            JARVISCalendarPairingView(nearby: nearby)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if nearby.socialLoading { ProgressView().controlSize(.small).tint(JARVISPalette.gold) }
            Text(nearby.socialStatus)
                .font(.system(size: 12))
                .foregroundStyle(JARVISPalette.muted)
                .lineLimit(2)
            Spacer()
            Button { nearby.refreshSocial() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(JARVISPalette.gold)
            .disabled(nearby.socialLoading)
            .accessibilityLabel("SNS 현황 새로고침")
        }
    }

    private var channelGrid: some View {
        let channels = nearby.socialSnapshot?.channels ?? []
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
            ForEach(channels) { channel in
                VStack(alignment: .leading, spacing: 5) {
                    Text(channel.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(JARVISPalette.gold)
                    Text(channel.followers.map { "\($0)" } ?? "—")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(JARVISPalette.white)
                    Text(channel.error ?? (channel.posts.map { "팔로워 · 게시물 \($0)" } ?? "팔로워"))
                        .font(.system(size: 9))
                        .foregroundStyle(channel.error == nil ? JARVISPalette.muted : .orange)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(JARVISPalette.panelEdge, lineWidth: 0.75))
            }
        }
    }

    private var emptyCard: some View {
        Text("검토할 캐러셀이 없어요. Mac 자비스가 매일 01:30에 새 위키 글로 만들어요.")
            .font(.system(size: 13))
            .foregroundStyle(JARVISPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 15))
    }

    private func carouselCard(_ carousel: JARVISSocialCarousel) -> some View {
        let reviewing = carousel.status == "review"
        let posted = carousel.status == "posted"
        let images = carousel.previews.compactMap { Data(base64Encoded: $0).flatMap(UIImage.init(data:)) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(reviewing ? "검토 대기" : posted ? "게시 완료" : "승인됨 · 22시 게시 대기")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((reviewing ? JARVISPalette.gold : Color.green).opacity(0.18), in: Capsule())
                    .foregroundStyle(reviewing ? JARVISPalette.gold : .green)
                Text(carousel.visualChecked ? "Claude 시각 검수 통과" : "시각 검수 미완료")
                    .font(.system(size: 11))
                    .foregroundStyle(carousel.visualChecked ? JARVISPalette.muted : .orange)
                Spacer()
            }
            Text(carousel.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(JARVISPalette.white)

            if !images.isEmpty {
                TabView(selection: $page) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .aspectRatio(1080.0 / 1350.0, contentMode: .fit)
                Text("\(page + 1) / \(images.count)" + (images.count < carousel.slideCount
                     ? " · 미리보기 \(images.count)장 (전체 \(carousel.slideCount)장)" : ""))
                    .font(.system(size: 11)).foregroundStyle(JARVISPalette.muted)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("캡션").font(.system(size: 11, weight: .semibold)).foregroundStyle(JARVISPalette.gold)
                Text(carousel.caption)
                    .font(.system(size: 13))
                    .foregroundStyle(JARVISPalette.white.opacity(0.9))
                    .lineLimit(showFullCaption ? nil : 5)
                    .textSelection(.enabled)
                Button(showFullCaption ? "접기" : "캡션 전체 보기") { showFullCaption.toggle() }
                    .font(.system(size: 12)).foregroundStyle(JARVISPalette.gold)
            }

            if posted, let link = carousel.permalink, let url = URL(string: link), !link.isEmpty {
                Link(destination: url) {
                    Label("인스타에서 보기", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered).tint(.green)
            }
            if let status = nearby.socialDecisionStatus {
                Text(status).font(.system(size: 12)).foregroundStyle(JARVISPalette.gold)
            }
            if reviewing {
                HStack(spacing: 10) {
                    Button { confirming = false } label: {
                        Label("반려", systemImage: "xmark").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered).tint(.gray)
                    Button { confirming = true } label: {
                        Label("승인", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(JARVISPalette.gold)
                }
                .disabled(nearby.socialDeciding)
            }
            Text("승인하면 Mac이 오늘 22시에 인스타에 자동 게시해요. 게시는 지금 본 이 버전으로만 진행되고, 바뀌면 다시 승인해야 해요.")
                .font(.system(size: 10)).foregroundStyle(JARVISPalette.muted)
        }
        .padding(15)
        .background(JARVISPalette.panel, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(JARVISPalette.panelEdge, lineWidth: 0.75))
        .confirmationDialog(confirming == true ? "이 캐러셀을 승인할까요?" : "이 캐러셀을 반려할까요?",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            Button(confirming == true ? "승인 · 게시 대기로" : "반려 · 게시 안 함",
                   role: confirming == true ? nil : .destructive) {
                if let approve = confirming { nearby.decideSocial(carousel, approve: approve) }
                confirming = nil
            }
            Button("취소", role: .cancel) { confirming = nil }
        } message: {
            Text(carousel.title)
        }
    }
}
