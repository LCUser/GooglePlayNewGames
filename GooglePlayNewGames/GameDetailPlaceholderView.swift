import SwiftUI

struct GameDetailPlaceholderView: View {
    let gameID: String

    var body: some View {
        Text("Game detail")
            .navigationTitle("Detail")
    }
}

#Preview {
    NavigationStack {
        GameDetailPlaceholderView(gameID: "preview.game")
    }
}
