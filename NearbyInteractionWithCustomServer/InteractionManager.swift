import Combine
import Foundation
import NearbyInteraction

struct HTTPResponseBody: Decodable {
  let id: Int
  let token: String
  let success: Bool
}

class InteractionManager: NSObject, ObservableObject {
  // Please replace this URL with your Cloudflare Workers URL.
  static let apiURL = "https://interaction.moutend.workers.dev"

  var distance: AnyPublisher<Float, Never> {
    self.distanceSubject.eraseToAnyPublisher()
  }

  private let distanceSubject = PassthroughSubject<Float, Never>()

  @Published var myTokenId: Int = 0

  private var session: NISession? = nil
  private var peerToken: NIDiscoveryToken? = nil

  override init() {
    super.init()
    self.prepare()
  }
  func prepare() {
    var isSupported: Bool

    if #available(iOS 16.0, watchOS 9.0, *) {
      isSupported = NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    } else {
      isSupported = NISession.isSupported
    }
    if !isSupported {
      return
    }

    self.session = NISession()
    session?.delegate = self
  }
  func getMyToken() {
    guard let session = self.session else {
      return
    }
    guard let myToken = session.discoveryToken else {
      return
    }
    guard
      let myTokenData = try? NSKeyedArchiver.archivedData(
        withRootObject: myToken, requiringSecureCoding: true)
    else {
      return
    }

    let endpoint = URL(string: InteractionManager.apiURL)!
    let requestBody: [String: String] = [
      "token": myTokenData.base64EncodedString()
    ]

    var request = URLRequest(url: endpoint)

    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
    } catch {
      print("Failed to set httpBody: \(error)")
      return
    }

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        print("Failed to send HTTP GET request: \(error)")
        return
      }
      if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        print("Unexpected HTTP status code")
        return
      }
      guard let data = data else {
        print("Response body is empty")
        return
      }
      do {
        let responseBody = try JSONDecoder().decode(HTTPResponseBody.self, from: data)

        if !responseBody.success {
          print("Failed to call API")
          return
        }
        DispatchQueue.main.async {
          self.myTokenId = responseBody.id
        }
      } catch {
        print("Failed to parse response body: \(error)")
      }
    }

    task.resume()
  }
  func getPeerToken(id: Int) {
    let endpoint = URL(string: "\(InteractionManager.apiURL)/\(id)")!

    var request = URLRequest(url: endpoint)

    request.httpMethod = "GET"

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        print("Failed to send HTTP POST request: \(error)")
        return
      }
      if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        print("Unexpected HTTP status code")
        return
      }
      guard let data = data else {
        print("Response body is empty")
        return
      }
      do {
        let responseBody = try JSONDecoder().decode(HTTPResponseBody.self, from: data)

        if !responseBody.success {
          print("Failed to call API")
          return
        }

        guard let peerTokenData = Data(base64Encoded: responseBody.token) else {
          print("Failed to decode response body")
          return
        }

        let peerToken = try NSKeyedUnarchiver.unarchivedObject(
          ofClass: NIDiscoveryToken.self, from: peerTokenData)

        self.peerToken = peerToken
      } catch {
        print("Failed to set peer token: \(error)")
      }
    }

    task.resume()
  }
  func run() {
    guard let peerToken = self.peerToken else {
      return
    }

    let configuration = NINearbyPeerConfiguration(peerToken: peerToken)

    guard let session = self.session else {
      return
    }

    session.run(configuration)
  }
  func invalidate() {
    guard let session = self.session else {
      return
    }

    session.invalidate()
  }
}

extension InteractionManager: NISessionDelegate {
  func sessionDidStartRunning(_ session: NISession) {
    print("The session starts or resumes running")
  }
  func session(_ session: NISession, didUpdate: [NINearbyObject]) {
    print("The session updates nearby objects")
    for update in didUpdate {
      guard let distance = update.distance else {
        continue
      }
      DispatchQueue.main.async {
        self.distanceSubject.send(distance)
      }
    }
  }
  func session(
    _ session: NISession, didRemove: [NINearbyObject], reason: NINearbyObject.RemovalReason
  ) {
    print("The session removes one or more nearby objects")
  }
  func sessionWasSuspended(_ session: NISession) {
    print("Suspended session")
  }
  func sessionSuspensionEnded(_ session: NISession) {
    print("The end of a session’s suspension")
  }
  func session(_ session: NISession, didInvalidateWith: Error) {
    print("Invalidated session")
  }
}
