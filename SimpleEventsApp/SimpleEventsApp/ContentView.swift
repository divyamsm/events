import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let containerHeight = proxy.size.height
                let events = EventRepository.sampleEvents

                Group {
                    if #available(iOS 17.0, *) {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(events) { event in
                                    VStack {
                                        Spacer(minLength: 0)
                                        EventCardView(event: event)
                                            .frame(height: containerHeight * 0.75)
                                            .padding(.horizontal, 24)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(height: containerHeight)
                                }
                            }
                        }
                        .scrollTargetBehavior(.paging)
                    } else {
                        VerticalCarouselFallback(events: events, containerSize: proxy.size)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Upcoming Events")
        }
    }
}

#Preview {
    ContentView()
}

private struct EventCardView: View {
    let event: Event

    private let cornerRadius: CGFloat = 28

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let gradient = LinearGradient(
                gradient: Gradient(colors: [.black.opacity(0.78), .black.opacity(0.12)]),
                startPoint: .bottom,
                endPoint: .top
            )

            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: event.imageURL, transaction: Transaction(animation: .easeInOut)) { phase in
                    image(for: phase, size: size)
                }
                .frame(width: size.width, height: size.height)

                gradient
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)

                cardText
                    .padding(24)
                    .frame(width: size.width, alignment: .leading)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(shape)
            .compositingGroup()
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.05)))
            .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 12)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func image(for phase: AsyncImagePhase, size: CGSize) -> some View {
        switch phase {
        case .empty:
            placeholder
                .frame(width: size.width, height: size.height)
        case .success(let image):
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
        case .failure:
            placeholderIcon
                .frame(width: size.width, height: size.height)
        @unknown default:
            placeholder
                .frame(width: size.width, height: size.height)
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 60)
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.systemGray5)
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.8))
        }
    }

    private var cardText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(event.location)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            VStack(alignment: .leading, spacing: 4) {
                Text(relativeFormatter.localizedString(for: event.date, relativeTo: .now))
                    .font(.subheadline.weight(.semibold))
                Text(absoluteFormatter.string(from: event.date))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

private struct VerticalCarouselFallback: View {
    let events: [Event]
    let containerSize: CGSize

    var body: some View {
        TabView {
            ForEach(events) { event in
                EventCardView(event: event)
                    .frame(width: containerSize.width * 0.82, height: containerSize.height * 0.75)
                    .padding(.horizontal, 24)
                    .rotationEffect(.degrees(-90))
                    .frame(width: containerSize.height, height: containerSize.width)
            }
        }
        .frame(width: containerSize.height, height: containerSize.width)
        .rotationEffect(.degrees(90), anchor: .topLeading)
        .offset(x: containerSize.width)
        .frame(width: containerSize.width, height: containerSize.height)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }
}
