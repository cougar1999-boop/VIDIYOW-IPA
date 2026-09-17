import UIKit
import AVFoundation

final class NativePlayerViewController: UIViewController {
    private let streamURL: URL
    private let mediaTitle: String
    private let mediaType: String
    private let year: String
    private let portal: String
    private let referer: String
    private let userAgent: String

    private var player: AVPlayer!
    private var playerLayer: AVPlayerLayer!
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var stallTimer: Timer?
    private var saveTimer: Timer?
    private var lastLiveTime: Double = -1
    private var lastLiveProgressAt = Date()
    private var liveRecoveryCount = 0
    private var lastLiveRecoveryAt = Date.distantPast
    private var vodRetryCount = 0
    private var resumePosition: Double = 0
    private var resumePromptShown = false
    private var subtitleCues: [SubtitleCue] = []
    private var subtitleLabel: UILabel!
    private var subtitleSearchResults: [(language: String, label: String, fileID: String)] = []

    private let spinner = UIActivityIndicatorView(style: .large)
    private let loadingLabel = UILabel()
    private let ccButton = UIButton(type: .system)
    private let controls = UIView()
    private let playPauseButton = UIButton(type: .system)
    private let seekBackButton = UIButton(type: .system)
    private let seekForwardButton = UIButton(type: .system)
    private let progress = UISlider()
    private let timeLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private var controlsTimer: Timer?
    private var isSeeking = false

    init(url: String, title: String, mediaType: String, year: String, portal: String, referer: String, userAgent: String) {
        self.streamURL = URL(string: url) ?? URL(string: "about:blank")!
        self.mediaTitle = title
        self.mediaType = mediaType
        self.year = year
        self.portal = portal
        self.referer = referer
        self.userAgent = userAgent.isEmpty ? VIDIYOWConstants.defaultUserAgent : userAgent
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var isVOD: Bool { mediaType == "movie" || mediaType == "episode" }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var shouldAutorotate: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureAudioSession()
        view.backgroundColor = .black
        setupUI()
        resumePosition = isVOD ? loadResume() : 0
        configurePlayer()
        if isVOD {
            searchSubtitles()
            startResumeSaver()
        } else {
            startLiveWatchdog()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hideControlsSoon()
    }

    override func viewWillDisappear(_ animated: Bool) {
        if isVOD { saveResume(player?.currentTime().seconds ?? 0) }
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        if isVOD { saveResume(player?.currentTime().seconds ?? 0) }
        super.viewDidDisappear(animated)
    }

    deinit {
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = failureObserver { NotificationCenter.default.removeObserver(observer) }
        stallTimer?.invalidate()
        saveTimer?.invalidate()
        controlsTimer?.invalidate()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("VIDIYOW audio session error: \(error)")
        }
    }

    private func setupUI() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        view.addGestureRecognizer(tap)

        subtitleLabel = UILabel()
        subtitleLabel.textColor = .white
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        subtitleLabel.font = UIFont.systemFont(ofSize: 22, weight: .medium)
        subtitleLabel.layer.cornerRadius = 5
        subtitleLabel.layer.masksToBounds = true
        subtitleLabel.isHidden = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        view.addSubview(spinner)

        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.textColor = .white
        loadingLabel.font = .systemFont(ofSize: 14, weight: .medium)
        loadingLabel.textAlignment = .center
        view.addSubview(loadingLabel)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -25),
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 18),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 45),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -45),
            subtitleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, multiplier: 0.22)
        ])

        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        controls.layer.cornerRadius = 12
        view.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            controls.heightAnchor.constraint(equalToConstant: 58)
        ])

        styleButton(closeButton, title: "✕")
        styleButton(seekBackButton, title: "↶ 10")
        styleButton(playPauseButton, title: "▶")
        styleButton(seekForwardButton, title: "10 ↷")
        styleButton(ccButton, title: "CC")

        timeLabel.textColor = .white
        timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.text = "0:00 / 0:00"

        progress.minimumValue = 0
        progress.maximumValue = 1
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.addTarget(self, action: #selector(progressChanged(_:)), for: .valueChanged)
        progress.addTarget(self, action: #selector(progressTouchDown(_:)), for: .touchDown)
        progress.addTarget(self, action: #selector(progressTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        closeButton.addTarget(self, action: #selector(closePlayer), for: .touchUpInside)
        seekBackButton.addTarget(self, action: #selector(seekBack), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        seekForwardButton.addTarget(self, action: #selector(seekForward), for: .touchUpInside)
        ccButton.addTarget(self, action: #selector(showSubtitleMenu), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [closeButton, seekBackButton, playPauseButton, seekForwardButton, progress, timeLabel, ccButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        controls.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: controls.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: controls.bottomAnchor, constant: -5),
            progress.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
        ccButton.isHidden = !isVOD
        controls.isHidden = false
    }

    private func styleButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        button.layer.cornerRadius = 17
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }

    private func configurePlayer() {
        showLoading(isVOD ? "Film laden…" : "Kanaal laden…")
        let options: [String: Any] = [
            AVURLAssetHTTPUserAgentKey: userAgent,
            AVURLAssetHTTPHeaderFieldsKey: ["Accept": "*/*", "User-Agent": userAgent, "Referer": referer].filter { !$0.value.isEmpty }
        ]
        let asset = AVURLAsset(url: streamURL, options: options)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = isVOD ? 60.0 : 15.0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        player.isMuted = false
        player.volume = 1.0
        player.actionAtItemEnd = .pause

        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        view.layer.insertSublayer(playerLayer, at: 0)

        statusObservation = item.observe(\AVPlayerItem.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if item.status == .readyToPlay {
                    self.hideLoading()
                    if self.isVOD && self.resumePosition > 10 {
                        self.player?.pause()
                        self.showResumeDialog()
                    } else {
                        self.player?.play()
                        self.hideControlsSoon()
                    }
                } else if item.status == .failed {
                    if self.isVOD { self.saveResume(self.player?.currentTime().seconds ?? 0) }
                    self.recoverPlayback()
                }
            }
        }

        timeControlObservation = player.observe(\AVPlayer.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.hideLoading()
                    self.updatePlayButton()
                case .waitingToPlayAtSpecifiedRate:
                    if self.isVOD && player.currentTime().seconds < 3 { self.showLoading("Film laden…") }
                case .paused:
                    self.updatePlayButton()
                @unknown default: break
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.isVOD { self.clearResume() }
            self.hideLoading()
        }

        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.isVOD { self.saveResume(self.player?.currentTime().seconds ?? 0) }
        }

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.updateUI(time: time.seconds)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = view.bounds
    }

    private func showLoading(_ text: String) {
        loadingLabel.text = text
        spinner.startAnimating()
        spinner.isHidden = false
        loadingLabel.isHidden = false
    }

    private func hideLoading() {
        spinner.stopAnimating()
        spinner.isHidden = true
        loadingLabel.isHidden = true
    }

    private func updateUI(time: Double) {
        guard time.isFinite else { return }
        let duration = player?.currentItem?.duration.seconds ?? 0
        if duration.isFinite && duration > 0 {
            progress.value = Float(max(0, min(1, time / duration)))
            timeLabel.text = "\(format(time)) / \(format(duration))"
            progress.isHidden = false
            timeLabel.isHidden = false
        } else {
            progress.isHidden = true
            timeLabel.text = format(time)
        }
        updatePlayButton()
        updateSubtitle(time: time)
    }

    private func updatePlayButton() {
        playPauseButton.setTitle(player?.timeControlStatus == .playing ? "❚❚" : "▶", for: .normal)
    }

    private func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.isFinite ? seconds : 0))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    @objc private func toggleControls() {
        controls.isHidden.toggle()
        if !controls.isHidden { hideControlsSoon() }
    }

    private func hideControlsSoon() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.controls.isHidden = true
        }
    }

    @objc private func togglePlay() {
        if player?.timeControlStatus == .playing { player?.pause() } else { player?.play() }
        hideControlsSoon()
    }

    @objc private func seekBack() { seek(by: -10) }
    @objc private func seekForward() { seek(by: 10) }
    private func seek(by delta: Double) {
        guard let p = player else { return }
        let now = p.currentTime().seconds
        p.seek(to: CMTime(seconds: max(0, now + delta), preferredTimescale: 600))
        if isVOD { saveResume(max(0, now + delta)) }
        hideControlsSoon()
    }

    @objc private func progressTouchDown(_ sender: UISlider) { isSeeking = true }
    @objc private func progressChanged(_ sender: UISlider) {
        guard isSeeking, let duration = player?.currentItem?.duration.seconds, duration > 0 else { return }
        timeLabel.text = "\(format(Double(sender.value) * duration)) / \(format(duration))"
    }
    @objc private func progressTouchUp(_ sender: UISlider) {
        isSeeking = false
        guard let duration = player?.currentItem?.duration.seconds, duration > 0 else { return }
        let target = Double(sender.value) * duration
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        if isVOD { saveResume(target) }
        hideControlsSoon()
    }

    @objc private func closePlayer() { dismiss(animated: true) }

    private func resumeKey() -> String {
        let raw = "\(mediaType)|\(mediaTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(year.trimmingCharacters(in: .whitespacesAndNewlines))|\(portal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        return VIDIYOWConstants.resumePrefix + raw.data(using: .utf8)!.base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
    }

    private func saveResume(_ position: Double) {
        guard isVOD, position > 10 else { return }
        UserDefaults.standard.set(position, forKey: resumeKey())
    }

    private func loadResume() -> Double { UserDefaults.standard.double(forKey: resumeKey()) }
    private func clearResume() { UserDefaults.standard.removeObject(forKey: resumeKey()); resumePosition = 0 }

    private func showResumeDialog() {
        guard !resumePromptShown, resumePosition > 10 else { player?.play(); return }
        resumePromptShown = true
        let alert = UIAlertController(title: mediaTitle.isEmpty ? "Verder kijken" : mediaTitle,
                                      message: "Je was gebleven op \(format(resumePosition)).\n\nWil je vanaf hier verdergaan of opnieuw vanaf het begin starten?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Vanaf begin", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.clearResume()
            self.player?.seek(to: .zero)
            self.player?.play()
            self.hideControlsSoon()
        })
        alert.addAction(UIAlertAction(title: "Vanaf hier", style: .default) { [weak self] _ in
            guard let self else { return }
            self.player?.seek(to: CMTime(seconds: self.resumePosition, preferredTimescale: 600))
            self.player?.play()
            self.hideControlsSoon()
        })
        present(alert, animated: true)
    }

    private func recoverPlayback() {
        if isVOD {
            guard vodRetryCount < 6 else { return }
            vodRetryCount += 1
            let position = max(player?.currentTime().seconds ?? 0, loadResume())
            saveResume(position)
            showLoading("Film herstellen…")
            DispatchQueue.main.asyncAfter(deadline: .now() + min(4, Double(vodRetryCount) * 0.5)) { [weak self] in
                self?.recreatePlayer(at: position)
            }
        } else {
            let now = Date()
            guard liveRecoveryCount < 2, now.timeIntervalSince(lastLiveRecoveryAt) >= 30 else { return }
            liveRecoveryCount += 1
            lastLiveRecoveryAt = now
            showLoading("Live stream herstellen…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.recreatePlayer(at: 0) }
        }
    }

    private func recreatePlayer(at position: Double) {
        guard !isBeingDismissed else { return }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        let options: [String: Any] = [
            AVURLAssetHTTPUserAgentKey: userAgent,
            AVURLAssetHTTPHeaderFieldsKey: ["Accept": "*/*", "User-Agent": userAgent, "Referer": referer].filter { !$0.value.isEmpty }
        ]
        let asset = AVURLAsset(url: streamURL, options: options)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = isVOD ? 60.0 : 15.0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        player?.replaceCurrentItem(with: item)
        player?.automaticallyWaitsToMinimizeStalling = true
        player?.isMuted = false
        player?.volume = 1.0
        statusObservation = item.observe(\AVPlayerItem.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            if item.status == .readyToPlay {
                if self.isVOD && position > 0 { self.player?.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
                self.hideLoading()
                self.player?.play()
            } else if item.status == .failed { self.recoverPlayback() }
        }
    }

    private func startResumeSaver() {
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isVOD else { return }
            self.saveResume(self.player?.currentTime().seconds ?? 0)
        }
    }

    private func startLiveWatchdog() {
        lastLiveProgressAt = Date()
        lastLiveTime = -1
        stallTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, let p = self.player else { return }
            let now = Date()
            let t = p.currentTime().seconds
            if p.rate > 0, t.isFinite {
                if self.lastLiveTime < 0 || t > self.lastLiveTime + 0.5 {
                    self.lastLiveTime = t
                    self.lastLiveProgressAt = now
                }
                if now.timeIntervalSince(self.lastLiveProgressAt) >= 45 { self.recoverPlayback(); self.lastLiveProgressAt = now }
            } else if p.timeControlStatus == .waitingToPlayAtSpecifiedRate && now.timeIntervalSince(self.lastLiveProgressAt) >= 30 {
                self.recoverPlayback(); self.lastLiveProgressAt = now
            }
        }
    }

    private func searchSubtitles(completion: ((Bool) -> Void)? = nil) {
        guard isVOD, !mediaTitle.isEmpty else { completion?(false); return }
        var components = URLComponents(string: VIDIYOWConstants.subtitleAPI)
        components?.queryItems = [
            URLQueryItem(name: "action", value: "search"),
            URLQueryItem(name: "title", value: mediaTitle),
            URLQueryItem(name: "year", value: year)
        ]
        guard let url = components?.url else { completion?(false); return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self, error == nil, let data,
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = root["results"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            var results: [(String,String,String)] = []
            for item in items {
                let lang = (item["language"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let fileID = (item["file_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !lang.isEmpty && !fileID.isEmpty { results.append((lang, self.subtitleLabel(for: lang), fileID)) }
            }
            DispatchQueue.main.async {
                self.subtitleSearchResults = results
                completion?(!results.isEmpty)
            }
        }.resume()
    }

    @objc private func showSubtitleMenu() {
        guard isVOD else { return }
        if subtitleSearchResults.isEmpty {
            showLoading("Ondertitels zoeken…")
            searchSubtitles { [weak self] found in
                guard let self else { return }
                self.hideLoading()
                if found { self.presentSubtitleMenu() }
                else {
                    let alert = UIAlertController(title: "Ondertitels", message: "Geen ondertitels gevonden.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Opnieuw zoeken", style: .default) { [weak self] _ in self?.searchSubtitles() })
                    alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                    self.present(alert, animated: true)
                }
            }
        } else {
            presentSubtitleMenu()
        }
    }

    private func presentSubtitleMenu() {
        let alert = UIAlertController(title: "Ondertitels", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Uit", style: .default) { [weak self] _ in
            self?.subtitleCues.removeAll(); self?.subtitleLabel.isHidden = true
        })
        for result in subtitleSearchResults {
            alert.addAction(UIAlertAction(title: result.label, style: .default) { [weak self] _ in
                self?.loadSubtitle(fileID: result.fileID, language: result.language)
            })
        }
        alert.addAction(UIAlertAction(title: "Opnieuw zoeken", style: .default) { [weak self] _ in self?.searchSubtitles() })
        alert.addAction(UIAlertAction(title: "Annuleren", style: .cancel))
        if let pop = alert.popoverPresentationController { pop.sourceView = ccButton; pop.sourceRect = ccButton.bounds }
        present(alert, animated: true)
    }

    private func loadSubtitle(fileID: String, language: String) {
        var components = URLComponents(string: VIDIYOWConstants.subtitleAPI)
        components?.queryItems = [URLQueryItem(name: "action", value: "download"), URLQueryItem(name: "file_id", value: fileID)]
        guard let url = components?.url else { return }
        showLoading("Subtitle laden…")
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self, error == nil, let data,
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { self?.hideLoading() }
                return
            }
            let cues = SubtitleParser.parse(text)
            DispatchQueue.main.async {
                self.subtitleCues = cues
                self.subtitleLabel.isHidden = cues.isEmpty
                self.hideLoading()
                _ = language
            }
        }.resume()
    }

    private func subtitleLabel(for language: String) -> String {
        switch language.lowercased() {
        case "en": return "English"
        case "nl": return "Nederlands"
        case "de": return "Deutsch"
        case "fr": return "Français"
        case "es": return "Español"
        case "it": return "Italiano"
        case "pt": return "Português"
        case "pl": return "Polski"
        case "tr": return "Türkçe"
        default: return language.uppercased()
        }
    }

    private func updateSubtitle(time: Double) {
        guard let cue = subtitleCues.first(where: { time >= $0.start && time <= $0.end }) else { subtitleLabel.isHidden = true; return }
        subtitleLabel.text = cue.text
        subtitleLabel.isHidden = false
    }
}

private struct SubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

private enum SubtitleParser {
    static func parse(_ source: String) -> [SubtitleCue] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var result: [SubtitleCue] = []
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard let timingIndex = lines.firstIndex(where: { $0.contains(" --> ") }) else { continue }
            let timing = lines[timingIndex]
            let parts = timing.components(separatedBy: " --> ")
            guard parts.count >= 2, let start = parseTime(parts[0]), let end = parseTime(parts[1].split(separator: " ").first.map(String.init) ?? parts[1]) else { continue }
            let text = lines[(timingIndex + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(SubtitleCue(start: start, end: end, text: text)) }
        }
        return result.sorted { $0.start < $1.start }
    }

    static func parseTime(_ value: String) -> Double? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = v.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return nil }
        if parts.count == 3 {
            return (Double(parts[0]) ?? 0) * 3600 + (Double(parts[1]) ?? 0) * 60 + (Double(parts[2]) ?? 0)
        }
        return (Double(parts[0]) ?? 0) * 60 + (Double(parts[1]) ?? 0)
    }
}
