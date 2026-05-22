/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A view for adding a new trip.
*/

import SwiftUI
import PhotosUI

/// A view for adding a new trip.
struct AddTripView: View {

    /// The data source used to add the new trip.
    @Environment(DataSource.self) private var dataSource

    /// The model used in creating a new trip.
    @State private var model = Model()

    /// Indicates whether the confirmation dialog is shown.
    ///
    /// This is used to keep people from losing changes by accidentally
    /// dismissing the sheet.
    @State private var isDiscardConfirmationShowing = false

    /// Indicates whether the sheet is presented.
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .center, spacing: 34) {
                TripImagePicker(selectedPhotoURL: $model.selectedPhotoURL)

                TripDetailsForm()
            }
            .padding()
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .environment(model)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(role: .close) {
                        if model.hasChanges {
                            isDiscardConfirmationShowing = true
                        } else {
                            isPresented = false
                        }
                    }
                    .confirmationDialog("Discard changes?", isPresented: $isDiscardConfirmationShowing) {
                        Button(role: .destructive) {
                            isPresented = false
                        } label: {
                            Text("Discard")
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(role: .confirm) {
                        if let photoURL = model.selectedPhotoURL {
                            dataSource.addTrip(
                                name: model.name,
                                collection: model.selectedCollection,
                                photoURL: photoURL
                            )
                        }
                        isPresented = false
                    }
                    .disabled(!model.canSave)
                }
            }
            .interactiveDismissDisabled(model.hasChanges)
        }
    }
}

/// A photo picker view for selecting trip images from the photo library.
private struct TripImagePicker: View {

    /// The currently selected photo from the picker.
    @State private var selectedPhoto: PhotosPickerItem?

    /// A binding to the URL where the selected image is saved.
    @Binding var selectedPhotoURL: URL?

    var body: some View {
        PhotosPicker(
            selection: $selectedPhoto,
            matching: .images,
            photoLibrary: .shared()
        ) {
            AsyncImage(url: selectedPhotoURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Rectangle()
                        .fill(.ultraThickMaterial)

                    Image(systemName: "photo.circle")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.multicolor)
                        .tint(.accentColor)
                }
            }
            .frame(width: 185, height: 185)
            .clipShape(.rect(cornerRadius: 16))
        }
        .task(id: selectedPhoto) {
            if let newPhoto = selectedPhoto {
                // Save image to temporary directory and get the URL.
                do {
                    if let data = try await newPhoto.loadTransferable(type: Data.self) {
                        selectedPhotoURL = try saveImageToTemporaryDirectory(data: data)
                    }
                } catch {
                    print("Failed to load image: \(error)")
                }
            }
        }
    }
}

private extension TripImagePicker {

    /// Saves image data to a temporary file in the system's temporary directory.
    ///
    /// - Parameter data: The image data to save to the temporary directory.
    /// - Returns: A file URL pointing to the saved image file in the temporary directory.
    /// - Throws: An error if the file cannot be written to the temporary directory.
    func saveImageToTemporaryDirectory(data: Data) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        return fileURL
    }
}

/// A form view containing the trip details input fields.
private struct TripDetailsForm: View {
    
    /// The model used in creating a new trip.
    @Environment(Model.self) private var model

    var body: some View {
        Form {
            TripTitleField(model: model)

            TripGroupPicker(model: model)
        }
        .scrollContentBackground(.hidden)
    }
}

/// A text field for entering the trip title.
private struct TripTitleField: View {
    /// The model used in creating a new trip.
    @Bindable var model: Model

    var body: some View {
        TextField("Trip Title", text: $model.name)
    }
}

/// A picker for selecting the trip collection/group.
private struct TripGroupPicker: View {

    /// The model used in creating a new trip.
    @Bindable var model: Model

    var body: some View {
        Picker("Collection", selection: $model.selectedCollection) {
            ForEach(TripCollection.allCases) { collection in
                Text(collection.name)
                    .tag(collection)
            }
        }
    }
}

@Observable
private class Model {
    /// The URL where the selected image is saved.
    var selectedPhotoURL: URL?

    /// The name for the new trip.
    var name = ""

    /// The collection to add the new trip to.
    var selectedCollection: TripCollection = .winterRetreats

    /// Whether properties of the model have been filled in.
    ///
    /// This is used to enable the "save" checkmark.
    var canSave: Bool {
        selectedPhotoURL != nil && !name.isEmpty
    }

    /// Whether properties of the model have been edited.
    ///
    /// This is used to decide whether dismissing the sheet should require
    /// confirmation to avoid losing work.
    var hasChanges: Bool {
        selectedPhotoURL != nil || !name.isEmpty || selectedCollection != .winterRetreats
    }
}

private extension DataSource {
    /// Adds a new trip to the specified collection.
    ///
    /// - Parameters:
    ///   - name: The display name for the new trip. Should be non-empty.
    ///   - collection: The collection the trip belongs to.
    ///   - photoURL: The file URL pointing to the trip's associated image.
    func addTrip(name: String, collection: TripCollection, photoURL: URL) {
        let newTrip = Trip(name: name, collection: collection, photoURL: photoURL)
        trips[newTrip.id] = newTrip
    }
}

#Preview {
    @Previewable var dataSource = DataSource()

    AddTripView(isPresented: .constant(true))
        .environment(dataSource)
}
