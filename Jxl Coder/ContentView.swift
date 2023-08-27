//
//  ContentView.swift
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 25/08/2023.
//

import SwiftUI
#if canImport(JxlCoder)
import JxlCoder
#endif

struct ContentView: View {

    @State var firstImage: UIImage?
    @State var secondImage: UIImage?
    @State var thirdImage: UIImage?

    var body: some View {
        VStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack {
                    if let firstImage {
                        Image(uiImage: firstImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }

                    if let secondImage {
                        Image(uiImage: secondImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }

                    if let thirdImage {
                        Image(uiImage: thirdImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
            }
        }
        .padding()
        .onAppear {
            let url1 = Bundle.main.url(forResource: "first", withExtension: "jxl")!
            let url2 = Bundle.main.url(forResource: "second", withExtension: "jxl")!
            let fImage = try! JXLCoder.decode(url: url1)
            let sImage = try! JXLCoder.decode(url: url2)
            firstImage = fImage
            secondImage = sImage
            let testEncImage = try! JXLCoder.encode(image: UIImage(named: "test_1")!, colorSpace: .rgb)
            thirdImage = try! JXLCoder.decode(data: testEncImage)

            Task { @MainActor in
                try await Task.sleep(nanoseconds: NSEC_PER_SEC * 5)
                secondImage = nil
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
