/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A view for adding a new trip.
*/

import SwiftUI
import PhotosUI
import SwiftData

/// A view for adding a new trip.
struct AddTripView: View {

    /// The model context for inserting the new trip.
    @Environment(\.modelContext) private var modelContext

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
                TripImagePicker(selectedPhotoData: $model.selectedPhotoData)

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
                        if let photoData = model.selectedPhotoData {
                            let newTrip = Trip(name: model.name, collection: model.selectedCollection, photo: TripImage(data: photoData))
                            modelContext.insert(newTrip)
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

    /// A binding to the data of the selected image.
    @Binding var selectedPhotoData: Data?

    var body: some View {
        PhotosPicker(
            selection: $selectedPhoto,
            matching: .images,
            photoLibrary: .shared()
        ) { [selectedPhotoData] in
            if let selectedPhotoData, let uiImage = UIImage(data: selectedPhotoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
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
        }
        .frame(width: 185, height: 185)
        .clipShape(.rect(cornerRadius: 16))
        .task(id: selectedPhoto) {
            if let newPhoto = selectedPhoto {
                do {
                    selectedPhotoData = try await newPhoto.loadTransferable(type: Data.self)
                } catch {
                    print("Failed to load image: \(error)")
                }
            }
        }
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
    /// The data of the selected image.
    var selectedPhotoData: Data?

    /// The name for the new trip.
    var name = ""

    /// The collection to add the new trip to.
    var selectedCollection: TripCollection = .winterRetreats

    /// Whether properties of the model have been filled in.
    ///
    /// This is used to enable the "save" checkmark.
    var canSave: Bool {
        selectedPhotoData != nil && !name.isEmpty
    }

    /// Whether properties of the model have been edited.
    ///
    /// This is used to decide whether dismissing the sheet should require
    /// confirmation to avoid losing work.
    var hasChanges: Bool {
        selectedPhotoData != nil || !name.isEmpty || selectedCollection != .winterRetreats
    }
}

#Preview {
    AddTripView(isPresented: .constant(true))
        .modelContainer(SampleData.previewContainer)
}
