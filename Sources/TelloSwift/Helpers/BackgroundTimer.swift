//
//  BackgroundTimer.swift
//  
//
//  Created by Boris Gromov on 17.06.2020.
//  
// Inspired by https://medium.com/over-engineering/a-background-repeating-timer-in-swift-412cecfd2ef9


import Foundation

internal class BackgroundTimer {
    private let timer: DispatchSourceTimer
    private let handler: ((BackgroundTimer) -> ())?

    private enum State {
        case suspended
        case resumed
        case cancelled
    }
    private var state: State = .suspended

    init(repeat interval: TimeInterval, event handler: @escaping (BackgroundTimer) -> ()) {
        self.handler = handler

        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.handler?(self!)
        }

        resume()
    }

//    deinit {
//        cancel()
//    }

    func resume() {
        guard state != .resumed && state != .cancelled else {
            return
        }

        state = .resumed
        timer.resume()
    }

    func suspend() {
        guard state != .suspended && state != .cancelled else {
            return
        }

        state = .suspended
        timer.suspend()
    }

    func cancel() {
        guard state != .cancelled else {
            return
        }

        state = .cancelled

        timer.setEventHandler {}
        timer.cancel()

        resume()
    }

    @inlinable func invalidate() {
        cancel()
    }
}
