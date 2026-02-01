import { Controller } from "@hotwired/stimulus";
import { pipeline, read_audio } from "@xenova/transformers";
import { initActiveStorage } from "juntos:active-storage";
import { Clip } from "juntos:models";

export default class DictaphoneController extends Controller {
  #analyser;
  #audioBlob;
  #audioContext;
  #audioDuration;
  #chunks;
  #isRecording;
  #mediaRecorder;
  #startTime;
  #timerInterval;
  #transcriber;

  static targets = [
    "status",
    "record",
    "recordLabel",
    "timer",
    "visualizer",
    "preview",
    "level",
    "audio",
    "duration",
    "name",
    "transcribing",
    "transcript",
    "audioData"
  ];

  connect() {
    this.#transcriber = null;
    this.#mediaRecorder = null;
    this.#audioContext = null;
    this.#analyser = null;
    this.#chunks = [];
    this.#startTime = null;
    this.#timerInterval = null;
    this.#isRecording = false;
    this.#audioBlob = null // Store audio blob for Active Storage;
    this.#audioDuration = null // Store recording duration;
    this.initStorage();
    return this.loadModel()
  };

  disconnect() {
    if (this.#isRecording) this.stopRecording();
    return this.#timerInterval && clearInterval(this.#timerInterval)
  };

  // Initialize Active Storage
  async initStorage() {
    {
      try {
        await initActiveStorage()
      } catch (error) {
        console.error("Failed to initialize Active Storage:", error)
      }
    }
  };

  // Load the Whisper model (downloads ~75MB on first use, cached after)
  async loadModel() {
    {
      try {
        this.#transcriber = await pipeline(
          "automatic-speech-recognition",
          "Xenova/whisper-tiny.en",

          {progress_callback: (progress) => {
            let pct;

            if (progress.status == "progress" && progress.progress) {
              pct = Math.round(progress.progress);
              return this.statusTarget.textContent = `Loading Whisper model... ${pct}%`
            } else if (progress.status == "ready") {
              return this.statusTarget.textContent = "Model loaded!"
            }
          }}
        );

        this.statusTarget.textContent = "Ready to record";
        this.statusTarget.classList.remove("bg-blue-50", "text-blue-800");
        this.statusTarget.classList.add("bg-green-50", "text-green-800");
        this.recordTarget.disabled = false
      } catch (error) {
        console.error("Failed to load Whisper model:", error);
        this.statusTarget.textContent = "Failed to load model. Please refresh and try again.";
        this.statusTarget.classList.remove("bg-blue-50", "text-blue-800");
        this.statusTarget.classList.add("bg-red-50", "text-red-800")
      }
    }
  };

  toggleRecording() {
    return this.#isRecording ? this.stopRecording() : this.startRecording()
  };

  async startRecording() {
    {
      try {
        let stream = await navigator.mediaDevices.getUserMedia({audio: true});

        // Set up audio analysis for visualizer
        this.#audioContext = new AudioContext;
        let source = this.#audioContext.createMediaStreamSource(stream);
        this.#analyser = this.#audioContext.createAnalyser();
        this.#analyser.fftSize = 256;
        source.connect(this.#analyser);

        // Determine best supported format
        let mimeType = MediaRecorder.isTypeSupported("audio/webm;codecs=opus") ? "audio/webm;codecs=opus" : "audio/mp4";
        this.#mediaRecorder = new MediaRecorder(stream, {mimeType});
        this.#chunks = [];

        this.#mediaRecorder.ondataavailable = (e) => {
          if (e.data.size > 0) return this.#chunks.push(e.data)
        };

        this.#mediaRecorder.onstop = () => {
          return this.handleRecordingComplete()
        };

        this.#mediaRecorder.start(100) // Collect data every 100ms;
        this.#isRecording = true;
        this.#startTime = Date.now();

        // Update UI
        this.recordLabelTarget.textContent = "Stop";
        this.recordTarget.classList.remove("bg-red-600", "hover:bg-red-700");
        this.recordTarget.classList.add("bg-gray-800", "hover:bg-gray-900");
        this.timerTarget.classList.remove("hidden");
        this.visualizerTarget.classList.remove("hidden");
        this.previewTarget.classList.add("hidden");

        // Start timer and visualizer
        this.updateTimer();

        this.#timerInterval = setInterval(
          () => {
            return this.updateTimer()
          },

          100
        );

        this.visualize()
      } catch (error) {
        console.error("Failed to start recording:", error);
        this.statusTarget.textContent = "Microphone access denied. Please allow microphone access.";
        this.statusTarget.classList.remove("bg-green-50", "text-green-800");
        this.statusTarget.classList.add("bg-red-50", "text-red-800")
      }
    }
  };

  stopRecording() {
    if (!this.#mediaRecorder || !this.#isRecording) return;
    this.#mediaRecorder.stop();

    for (let track of this.#mediaRecorder.stream.getTracks()) {
      track.stop()
    };

    this.#isRecording = false;
    if (this.#timerInterval) clearInterval(this.#timerInterval);
    if (this.#audioContext) this.#audioContext.close();

    // Update UI
    this.recordLabelTarget.textContent = "Record";

    this.recordTarget.classList.remove(
      "bg-gray-800",
      "hover:bg-gray-900"
    );

    this.recordTarget.classList.add("bg-red-600", "hover:bg-red-700");
    this.timerTarget.classList.add("hidden");
    return this.visualizerTarget.classList.add("hidden")
  };

  updateTimer() {
    if (!this.#startTime) return;
    let elapsed = (Date.now() - this.#startTime) / 1_000;
    let mins = Math.floor(elapsed / 60).toString().padStart(2, "0");
    let secs = Math.floor(elapsed % 60).toString().padStart(2, "0");
    return this.timerTarget.textContent = `${mins}:${secs}`
  };

  visualize() {
    if (!this.#analyser || !this.#isRecording) return;
    let dataArray = new Uint8Array(this.#analyser.frequencyBinCount);
    this.#analyser.getByteFrequencyData(dataArray);

    // Calculate average level
    let sum = 0;

    for (let value of dataArray) {
      sum += value
    };

    let average = sum / dataArray.length;
    let percentage = Math.min(100, (average / 128) * 100);
    this.levelTarget.style.width = `${percentage}%`;

    if (this.#isRecording) {
      return requestAnimationFrame(() => {
        return this.visualize()
      })
    }
  };

  async handleRecordingComplete() {
    // Create blob from chunks
    let mimeType = this.#mediaRecorder.mimeType;
    this.#audioBlob = new Blob(this.#chunks, {type: mimeType});
    this.#audioDuration = (Date.now() - this.#startTime) / 1_000;

    // Create playback URL
    let audioUrl = URL.createObjectURL(this.#audioBlob);
    this.audioTarget.src = audioUrl;

    // Set duration in form
    this.durationTarget.value = this.#audioDuration.toFixed(2);

    // Generate default name
    let now = new Date;
    this.nameTarget.value = `Recording ${now.toLocaleDateString()} ${now.toLocaleTimeString()}`;

    // Show preview
    this.previewTarget.classList.remove("hidden");
    return this.transcribe(this.#audioBlob)
  };

  async transcribe(blob) {
    if (!this.#transcriber) return;
    this.transcribingTarget.classList.remove("hidden");
    this.transcriptTarget.value = "";
    this.transcriptTarget.placeholder = "Transcribing...";

    try {
      try {
        // Create object URL for read_audio
        let audioUrl = URL.createObjectURL(blob);

        // Convert audio to Float32Array at 16kHz (Whisper's expected format)
        let audioData = await read_audio(audioUrl, 16_000);

        // Clean up object URL
        URL.revokeObjectURL(audioUrl);

        // Transcribe
        let result = await(this.#transcriber(audioData));
        this.transcriptTarget.value = result.text.trim();
        this.transcriptTarget.placeholder = "Transcription will appear here..."
      } catch (error) {
        console.error("Transcription failed:", error);
        this.transcriptTarget.placeholder = "Transcription failed. You can type manually."
      }
    } finally {
      this.transcribingTarget.classList.add("hidden")
    }
  };

  async save(event) {
    event.preventDefault();
    if (!this.#audioBlob) return;

    {
      try {
        // Create clip record first
        let clip = await Clip.create({
          name: this.nameTarget.value ?? "Untitled Recording",
          transcript: this.transcriptTarget.value,
          duration: parseFloat(this.durationTarget.value) ?? this.#audioDuration
        });

        // Attach audio via Active Storage
        let extension = this.#audioBlob.type.includes("webm") ? "webm" : "m4a";

        await clip.audio.attach(this.#audioBlob, {
          filename: `${clip.name.replaceAll(/[^a-z0-9]/gi, "_")}.${extension}`,
          content_type: this.#audioBlob.type
        });

        console.log("Clip saved with audio attachment:", clip.id);

        // Replace the initially-broadcast clip (which had no audio) with the full version
        await clip.broadcast_replace_to("clips");
        this.resetUI()
      } catch (error) {
        console.error("Failed to save clip:", error);
        this.statusTarget.textContent = "Failed to save clip. Please try again.";
        this.statusTarget.classList.remove("bg-green-50", "text-green-800");
        this.statusTarget.classList.add("bg-red-50", "text-red-800")
      }
    }
  };

  discard() {
    return this.resetUI()
  };

  resetUI() {
    // Revoke object URL
    if (this.audioTarget.src) URL.revokeObjectURL(this.audioTarget.src);

    // Clear stored blob
    this.#audioBlob = null;
    this.#audioDuration = null;

    // Clear form
    this.audioTarget.src = "";
    this.audioDataTarget.value = "";
    this.durationTarget.value = "";
    this.nameTarget.value = "";
    this.transcriptTarget.value = "";

    // Hide preview
    this.previewTarget.classList.add("hidden");

    // Reset status
    this.statusTarget.textContent = "Ready to record";
    this.statusTarget.classList.remove("bg-red-50", "text-red-800");

    return this.statusTarget.classList.add(
      "bg-green-50",
      "text-green-800"
    )
  }
}