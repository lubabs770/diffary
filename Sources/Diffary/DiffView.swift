import SwiftUI

struct DiffView: View {
    @ObservedObject var model: AppModel
    var body: some View { Text(model.selected?.path ?? "Select a file") }
}
