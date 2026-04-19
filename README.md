# Video Compressor (Ultra-Fast Compression)

A lightweight, high-performance batch video compression tool designed specifically for macOS. Built with SwiftUI for a native interface, it features a minimalist design with no complicated configuration—just drag and use.

## Features

- **Drag-and-Drop Interaction**: Simply drag video files or entire folders into the app to start processing.  
- **Deep Recursive Scanning**: Automatically detects all mainstream video formats (mp4, mov, mkv, avi, etc.) within folders and their subdirectories.  
- **Ultra-Fast Compression**: Uses preset optimized algorithms, including an “Extreme Compression” mode that significantly reduces file size while maintaining visual quality.  
- **Storage Savings Statistics**: Displays the number of compressed files and total disk space saved in real time.  
- **Automatic Cleanup**: Option to automatically move original videos to the Trash after compression, simplifying your workflow.  
- **Native Experience**: Fully developed with Swift/SwiftUI, supporting macOS localization (English and Chinese).  

## Technical Implementation

- **UI Framework**: SwiftUI (macOS App)  
- **Multithreading**: Utilizes Swift Concurrency (Actors, @MainActor) to ensure a smooth UI without blocking the main thread.  
- **Encoding Engine**: FFmpeg (invoked asynchronously via `Process`)  
- **Progress Tracking**: Parses FFmpeg output streams using regular expressions to provide real-time progress updates for both individual files and overall tasks.  

## Getting Started

### Requirements
- macOS 13.0+  
- The project must include a compiled `ffmpeg` binary (placed in the Resource directory).  