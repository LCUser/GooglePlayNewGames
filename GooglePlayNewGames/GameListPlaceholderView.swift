import SwiftUI

struct GameListPlaceholderView: View {
    var body: some View {
        NavigationLink("Open detail") {
            GameDetailPlaceholderView()
        }
        .navigationTitle("Games")
    }
}

#Preview {
    NavigationStack {
        GameListPlaceholderView()
    }
}
