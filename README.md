# 🎬 JumpCut – Smart Vlog Editing  

**JumpCut** is a **Zig**-powered tool that analyzes video or audio files, detects silence, and automatically generates a seamless timeline by keeping only the spoken sections. This helps vloggers and content creators streamline their editing process by removing silent gaps, optimizing video flow.  

## ✨ Features  

✅ **No external dependencies needed!!**.
✅ **Automatic silence detection** in video and audio files.  
✅ **Exports to editing formats** like  **EDL** (DaVinci Resolve, Premiere Pro).  
✅ **Efficient processing** powered by Zig’s speed and safety.  
✅ **Supports multiple input formats** (Currently MP4, with PCM 16-bit 48kHz audio).
✅ **Enhances the narrative flow** of vlogs and spoken content.  

## 🎯 Use Cases  

- **Vloggers and content creators** looking to speed up video editing.  
- **Podcasters** who want to remove pauses without manual editing.  
- **Interview and conference editing**, keeping only relevant speech.  

## 🚀 Installation  

1. **Clone the repository**:  
```bash
git clone https://github.com/DanielTowerz/jumpcut.git
```

2. **Build the project**:  
```bash
zig build --release=fast, safe or small
```

## 🛠️ Usage  
jumpcut -i <inputfile> -o <outputfile> -d <decibel> -s <silence duration> -a <adjustment>

-i: Input file path. [REQUIRED]
-o: Output file path. If not provided, the output will be saved in the same directory as the input file as `<inputfile name>.edl`.
-d: A negative number as decibel threshold for silence detection. Default is '-25'.  
-s: A positive float number as the minimum duration of silence to be detected. Default is '1.0' seconds.
-a: A positive float number as adjustment for the start and end of the detected silence. Default is '0.3' seconds.

```bash


## 📌 Roadmap  

- [ ] Export to **FCPXML**.  
- [ ] CLI interface with adjustable sensitivity settings.  
- [ ] Support for other video and audio formats.
<!--- [ ] Implement RMS/Threshold-based silence detection.  -->
<!--- [ ] Batch processing support for multiple files.  -->

