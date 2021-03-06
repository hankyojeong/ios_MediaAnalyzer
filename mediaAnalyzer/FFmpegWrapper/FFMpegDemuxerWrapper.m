//
//  FFMpegDemuxerWrapper.m
//  mediaAnalyzer
//
//  Created by HanGyo Jeong on 2020/08/02.
//  Copyright © 2020 HanGyoJeong. All rights reserved.
//

#import "FFMpegDemuxerWrapper.h"

@implementation FFMpegDemuxerWrapper

- (int)initFFMpegConfigWithPath:(NSString*)url {
    int err = 0;
    const char* input_file_name = [url UTF8String];
    
    av_register_all();
    
    if (avformat_open_input(&demuxer.fmt_ctx, input_file_name, NULL, NULL) < 0) {
        NSLog(@"[FFMpegDemuxerWrapper]Error: Failed to Open Input File\n");
        return -1;
    }
    
    if (avformat_find_stream_info(demuxer.fmt_ctx, NULL)) {
        NSLog(@"[FFMpegDemuxerWrapper]Error: Fail to Find Stream\n");
        return -1;
    }
    
    // Find Video Stream Index
    for (int index = 0; index < demuxer.fmt_ctx->nb_streams; index++) {
        AVCodecContext* codec_ctx = demuxer.fmt_ctx->streams[index]->codec;
        if (codec_ctx->codec_type == AVMEDIA_TYPE_VIDEO && demuxer.video_stream_index < 0) {
            if ([self open_decoder:codec_ctx] < 0) {
                break;
            }
            demuxer.video_stream_index = index;
        }
    }
    
    if (demuxer.video_stream_index < 0) {
        NSLog(@"[FFMpegDemuxerWrapper]Error: Failed tto retrieve video stream information");
    }
    
    AVStream* video_stream = NULL;
    video_stream = demuxer.fmt_ctx->streams[demuxer.video_stream_index];
    
    demuxer.codec = avcodec_find_decoder(video_stream->codecpar->codec_id);
    if (!demuxer.codec) {
        NSLog(@"[FFMpegDemuxerWrapper]Error: Fail to find decoder");
        return -1;
    }
    
    demuxer.codec_ctx = avcodec_alloc_context3(demuxer.codec);
    if (!demuxer.codec_ctx) {
        NSLog(@"[FFMpegDemuxerWrapper]Error: Failed allocate AVCodecContext instance");
        return -1;
    }
    
    if (avcodec_parameters_to_context(demuxer.codec_ctx, video_stream->codecpar) < 0) {
        NSLog(@"[FFMpegDemuxerWrapper]Error: Failed allocate AVCodecContext instance");
        return -1;
    }
    
    if (avcodec_open2(demuxer.codec_ctx, demuxer.codec, NULL) < 0) {
        NSLog(@"[FFMpegDemuxerWrapper]Error: Failed to opening codec");
        return -1;
    }
    
    // Initialize packet, set data to null
    av_init_packet(&demuxer.pkt);
    demuxer.pkt.data = NULL;
    demuxer.pkt.size = 0;
    
    return err;
}

- (int)open_decoder:(AVCodecContext*) codec_ctx {
    // Find the codec through Codec ID, ffmpeg try to find automatically
    AVCodec* decoder = avcodec_find_decoder(codec_ctx->codec_id);
    
    if (decoder == NULL) {
        return -1;
    }
    
    // Open the Decoder which ffmpeg automatically find previously
    if (avcodec_open2(codec_ctx, decoder, NULL) < 0) {
        return -2;
    }
    return 0;
}

- (AVCodecParameters*)getCodecParameters {
    AVCodecParameters* codecpar = avcodec_parameters_alloc();
    
    // Fill the parameters struct based on the values from the supplied codec
    if (avcodec_parameters_from_context(codecpar, demuxer.codec_ctx) < 0) {
        return NULL;
    }
    return codecpar;
}

- (int)get_video_packet:(NAL_UNIT*)nalu frameType:(void*)fType{
    int got_video_frame = 0;
    int* frameType = (int*)fType;
    while (av_read_frame(demuxer.fmt_ctx, &(demuxer.pkt)) >= 0) {
        if (demuxer.pkt.stream_index != demuxer.video_stream_index) {
            continue;
        }
        
        // Convert mp4 to annexb type
//        AVBitStreamFilterContext* bsf = av_bitstream_filter_init("h264_mp4toannexb");
//        AVStream* avStream = demuxer.fmt_ctx->streams[demuxer.video_stream_index];
//        AVCodecContext* codec_ctx = avStream->codec;
//        AVPacket new_pkt = (demuxer.pkt);
//        int ret = av_bitstream_filter_filter(bsf,
//                                             codec_ctx,
//                                             NULL,
//                                             &new_pkt.data,
//                                             &new_pkt.size,
//                                             demuxer.pkt.data,
//                                             demuxer.pkt.size,
//                                             demuxer.pkt.flags);
//        if (ret > 0) {
//            av_free_packet(&demuxer.pkt);
//            new_pkt.buf = av_buffer_create(new_pkt.data, new_pkt.size, av_buffer_default_free, NULL, 0);
//        }
//        demuxer.pkt = new_pkt;
        
//        av_packet_rescale_ts(&(demuxer.pkt), avStream->time_base, codec_ctx->time_base);
        
        // Convert annexb to avcC, Need Remuxing
        
        
        got_video_frame = 1;
        nalu->nal_size = demuxer.pkt.size;
        nalu->nal_buf = demuxer.pkt.data;
        
        // Print the Not Decoded (h264, or other codec type) bitstream
        NSLog(@"NAL Size : %d, %x", nalu->nal_size, nalu->nal_size);
//        printf("NOT Decoded Data--> \n");
        for (int i = 0; i < /*nalu->nal_size*/5; i++) {
            printf("[%x] ", (nalu->nal_buf)[i]);
        }
        switch ((nalu->nal_buf)[4]) {
            case 0x6:
            case 0x65:
                printf("I Frame \n");
                *frameType = 0;
                break;
            case 0x41:
                printf("P Frame \n");
                *frameType = 1;
                break;
            case 0x1:
                printf("B Frame \n");
                *frameType = 2;
                break;
            default:
                printf("Not Video Frame[%x] \n", (nalu->nal_buf)[4]);
                break;
        }
        break;
    }
    
    if (!got_video_frame) {
        return -1;
    }
    return 0;
}

- (void) ffmpeg_demuxer_release {
    if (demuxer.fmt_ctx) {
        avformat_close_input(&demuxer.fmt_ctx);
        demuxer.fmt_ctx = NULL;
    }
    
    if (demuxer.codec_ctx) {
        avcodec_free_context(&demuxer.codec_ctx);
    }
    
    NSLog(@"FFMpegWrapper is released.");
}

+ (FFDemuxer) getFFDemuxer {
    return demuxer;
}

@end
