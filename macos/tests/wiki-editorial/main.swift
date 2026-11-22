import Foundation
@main struct WikiEditorialSmoke {
    @MainActor static func main() async {
        let studio = JarvisWikiSocialStudio()
        await studio.proposeFromWiki()
        guard let draft = studio.draft else {
            print("DRAFT FAILED:",studio.notice)
            exit(1)
        }
        guard draft.sourceURL.hasPrefix("https://dechive.wiki/knowledge/"),
              !draft.facebook.isEmpty,
              !draft.instagram.isEmpty,
              !draft.threads.isEmpty,
              !draft.adProposal.isEmpty,
              !draft.reviewed else {
            fatalError("invalid local proposal")
        }
        print("DRAFT PASS | source:",draft.sourceTitle)
        print("characters:",draft.facebook.count,draft.instagram.count,draft.threads.count,draft.adProposal.count)
        print("reviewed:",draft.reviewed,"id:",draft.id.uuidString)
        print("saved in Mac Application Support; none published, no ad spend")
    }
}
