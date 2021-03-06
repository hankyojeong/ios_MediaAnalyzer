//
//  ViewController.swift
//  mediaAnalyzer
//
//  Created by HanGyo Jeong on 2020/08/02.
//  Copyright © 2020 HanGyoJeong. All rights reserved.
//

import UIKit
import MetalKit
import Metal
import Foundation

class VideoFrameAnalyzeViewController: DrawVideoViewController {

    // UI Components
    @IBOutlet weak var videoPreview: UIView!
    @IBOutlet weak var vfTableView: UITableView!
    
    // property
    var mediaPath: String?
    
    var demuxerWrapper: FFMpegDemuxerWrapper?
    var remuxerWrapper: FFMpegRemuxerWrapper?
    var videoToolboxDecoder: VideoToolboxDecoder?
    
    var objectToDraw: SquarePlain?

    var videoFrameDataArray: Array<FrameData> = [FrameData]()
    
    override func viewDidLoad() {
        
        super.metalVideoPreview = videoPreview
        super.mediaContentPath = mediaPath
        
        super.viewDidLoad()
        
        // Set tableview delegate
        vfTableView.delegate = self
        vfTableView.dataSource = self

        demuxerWrapper = FFMpegDemuxerWrapper()
        remuxerWrapper = FFMpegRemuxerWrapper()
        videoToolboxDecoder = VideoToolboxDecoder()
        
        if let metalDevice = device, let commandQ = commandQueue {
            objectToDraw = SquarePlain.init(metalDevice, commandQ: commandQ)
            super.metalViewControllerDelegate = self
        }
    
        videoToolboxDecoder?.delegate = self
        
        if var analyzeMedia = mediaPath {
            NSLog("media which analyzed: \(analyzeMedia)")
            
            // Start to Remuxing mpegts to mp4
            if analyzeMedia.hasSuffix(".ts") {
                guard let tsToMp4File = remuxerWrapper?.convertMpegts(toMp4: analyzeMedia), tsToMp4File != nil else {
                    return
                }
                analyzeMedia = tsToMp4File;
            }
            
            // Start to Demuxing
            guard let result = demuxerWrapper?.initFFMpegConfig(withPath: analyzeMedia), result == 0 else {
                NSLog("Failed to initialize the ffmpeg")
                return
            }
            
            if let demuxer = demuxerWrapper {
                guard let result = videoToolboxDecoder?.initWithExtradata(demuxer), result == 0 else {
                    NSLog("Failed to initialize the videoToolboxDecoder");
                    return
                }
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        DispatchQueue.global().async {
            self.runVideoToolboxDecoder()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // TODO: Close the Decoder
    }
    
    func runVideoToolboxDecoder() -> Int {
       
        while (true) {
            var pixelBufferRef: UnsafeMutablePointer<Unmanaged<CVPixelBuffer>?>? =
                UnsafeMutablePointer<Unmanaged<CVPixelBuffer>?>.allocate(capacity: 1)
            var frameExtraInfo: UnsafeMutablePointer<Int>? =
                UnsafeMutablePointer<Int>.allocate(capacity: 1)
            frameExtraInfo?.initialize(to: 0)
            
            if let err = videoToolboxDecoder?.decodeVideo(pixelBufferRef, frameType: frameExtraInfo!) {
                if (err < 0) {
                    break;
                }
                
                if let pixelBuffer = pixelBufferRef?.pointee?.takeRetainedValue() {
                    DispatchQueue.main.sync {
                        // TODO: Frame to Screen
                        if let commandQ = commandQueue, let pipeState = pipelineState, let drawable: CAMetalDrawable = metalLayer?.nextDrawable() {
                            objectToDraw?.render(commandQ,
                                                 renderPipelineState: pipeState,
                                                 drawable: drawable,
                                                 pixelBuffer: pixelBuffer)
                        }
                    }
                    // TODO: Release the pixelBuffer
                }
                pixelBufferRef?.deallocate()
            }
            if let frameType: Int = frameExtraInfo?[0] {
                let vframeData: FrameData? = FrameData(0, FrameType(rawValue: frameType))
                if let videoFrameData:FrameData = vframeData {
                    videoFrameDataArray.append(videoFrameData)
                }
            }
            frameExtraInfo?.deallocate()
            
            DispatchQueue.main.async {
                self.vfTableView.reloadData()
            }
            
            Thread.sleep(forTimeInterval: 0.025)
        }
        return 0
    }
}

extension VideoFrameAnalyzeViewController: MetalViewControllerDelegate {
    func updateLogic(timeSinceLasttUpdate: CFTimeInterval) {
        
    }
    
    func renderObject(drawable: CAMetalDrawable, pixelBuffer: CVPixelBuffer) {
//        if let commandQ = commandQueue, let pipeState = pipelineState {
//            objectToDraw?.render(commandQ,
//                                 renderPipelineState: pipeState,
//                                 drawable: drawable,
//                                 pixelBuffer: pixelBuffer)
//        }
    }
}

extension VideoFrameAnalyzeViewController: NALUnitDelegate {
    func nalUnitInfo(_ nal_buf_data: UnsafeMutablePointer<UInt8>, nalUnitSize nal_buf_size: Int32) {
//        let vFrameData: UnsafeMutablePointer<UInt64> = UnsafeMutablePointer<UInt64>.allocate(capacity: Int(nal_buf_size));
//        FFMpegUtil.convertMp4(toAnnexB: nal_buf_data)
//        NSLog("nal buf size %d", Int(nal_buf_size))
    }
}

extension VideoFrameAnalyzeViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return videoFrameDataArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = vfTableView.dequeueReusableCell(withIdentifier: "VFTableViewCell", for: indexPath) as! VFTableViewCell
        
        let row = indexPath.row
        cell.mediaFrameType.font = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.headline)
        if let videoFrameType = videoFrameDataArray[row].frameType {
            var vFrameText: String = "Not Recognized"
            switch videoFrameType {
            case .I_Frame:
                vFrameText = "I Frame"
                break;
            case .P_Frame:
                vFrameText = "P Frame"
                break;
            case .B_Frame:
                vFrameText = "B Frame"
                break
            default:
                vFrameText = "Not Video Frame"
                break
            }
            cell.mediaFrameType.text = vFrameText
        }
        return cell
    }
}
