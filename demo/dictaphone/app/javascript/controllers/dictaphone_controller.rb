# Whisper speech-to-text via Transformers.js
import ["pipeline", "read_audio"], from: '@xenova/transformers'
# Active Storage for audio file persistence
import ["initActiveStorage"], from: 'juntos:active-storage'
# Clip model for client-side persistence
import ["Clip"], from: 'juntos:models'

class DictaphoneController < Stimulus::Controller
  def connect
    @transcriber = nil
    @mediaRecorder = nil
    @audioContext = nil
    @analyser = nil
    @chunks = []
    @startTime = nil
    @timerInterval = nil
    @isRecording = false
    @audioBlob = nil      # Store audio blob for Active Storage
    @audioDuration = nil  # Store recording duration

    initStorage()
    loadModel()
  end

  def disconnect
    stopRecording() if @isRecording
    @timerInterval && clearInterval(@timerInterval)
  end

  # Initialize Active Storage
  async def initStorage
    begin
      await initActiveStorage()
    rescue => error
      console.error("Failed to initialize Active Storage:", error)
    end
  end

  # Load the Whisper model (downloads ~75MB on first use, cached after)
  async def loadModel
    begin
      @transcriber = await pipeline(
        'automatic-speech-recognition',
        'Xenova/whisper-tiny.en',
        progress_callback: ->(progress) {
          if progress.status == 'progress' && progress.progress
            pct = progress.progress.round
            statusTarget.textContent = "Loading Whisper model... #{pct}%"
          elsif progress.status == 'ready'
            statusTarget.textContent = "Model loaded!"
          end
        }
      )

      statusTarget.textContent = "Ready to record"
      statusTarget.classList.remove('bg-blue-50', 'text-blue-800')
      statusTarget.classList.add('bg-green-50', 'text-green-800')
      recordTarget.disabled = false
    rescue => error
      console.error("Failed to load Whisper model:", error)
      statusTarget.textContent = "Failed to load model. Please refresh and try again."
      statusTarget.classList.remove('bg-blue-50', 'text-blue-800')
      statusTarget.classList.add('bg-red-50', 'text-red-800')
    end
  end

  def toggleRecording
    if @isRecording
      stopRecording()
    else
      startRecording()
    end
  end

  async def startRecording
    begin
      stream = await navigator.mediaDevices.getUserMedia(audio: true)

      # Set up audio analysis for visualizer
      @audioContext = AudioContext.new
      source = @audioContext.createMediaStreamSource(stream)
      @analyser = @audioContext.createAnalyser()
      @analyser.fftSize = 256
      source.connect(@analyser)

      # Determine best supported format
      mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus') ?
                   'audio/webm;codecs=opus' : 'audio/mp4'

      @mediaRecorder = MediaRecorder.new(stream, mimeType: mimeType)
      @chunks = []

      @mediaRecorder.ondataavailable = ->(e) {
        @chunks.push(e.data) if e.data.size > 0
      }

      @mediaRecorder.onstop = -> { handleRecordingComplete() }

      @mediaRecorder.start(100) # Collect data every 100ms
      @isRecording = true
      @startTime = Date.now()

      # Update UI
      recordLabelTarget.textContent = "Stop"
      recordTarget.classList.remove('bg-red-600', 'hover:bg-red-700')
      recordTarget.classList.add('bg-gray-800', 'hover:bg-gray-900')
      timerTarget.classList.remove('hidden')
      visualizerTarget.classList.remove('hidden')
      previewTarget.classList.add('hidden')

      # Start timer and visualizer
      updateTimer()
      @timerInterval = setInterval(-> { updateTimer() }, 100)
      visualize()

    rescue => error
      console.error("Failed to start recording:", error)
      statusTarget.textContent = "Microphone access denied. Please allow microphone access."
      statusTarget.classList.remove('bg-green-50', 'text-green-800')
      statusTarget.classList.add('bg-red-50', 'text-red-800')
    end
  end

  def stopRecording
    return unless @mediaRecorder && @isRecording

    @mediaRecorder.stop()
    @mediaRecorder.stream.getTracks().each { |track| track.stop() }
    @isRecording = false

    clearInterval(@timerInterval) if @timerInterval
    @audioContext.close() if @audioContext

    # Update UI
    recordLabelTarget.textContent = "Record"
    recordTarget.classList.remove('bg-gray-800', 'hover:bg-gray-900')
    recordTarget.classList.add('bg-red-600', 'hover:bg-red-700')
    timerTarget.classList.add('hidden')
    visualizerTarget.classList.add('hidden')
  end

  def updateTimer
    return unless @startTime
    elapsed = (Date.now() - @startTime) / 1000
    mins = Math.floor(elapsed / 60).toString().padStart(2, '0')
    secs = Math.floor(elapsed % 60).toString().padStart(2, '0')
    timerTarget.textContent = "#{mins}:#{secs}"
  end

  def visualize
    return unless @analyser && @isRecording

    dataArray = Uint8Array.new(@analyser.frequencyBinCount)
    @analyser.getByteFrequencyData(dataArray)

    # Calculate average level
    sum = 0
    dataArray.each { |value| sum += value }
    average = sum / dataArray.length
    percentage = Math.min(100, (average / 128) * 100)

    levelTarget.style.width = "#{percentage}%"

    requestAnimationFrame(-> { visualize() }) if @isRecording
  end

  async def handleRecordingComplete
    # Create blob from chunks
    mimeType = @mediaRecorder.mimeType
    @audioBlob = Blob.new(@chunks, type: mimeType)
    @audioDuration = (Date.now() - @startTime) / 1000

    # Create playback URL
    audioUrl = URL.createObjectURL(@audioBlob)
    audioTarget.src = audioUrl

    # Set duration in form
    durationTarget.value = @audioDuration.toFixed(2)

    # Generate default name
    now = Date.new
    nameTarget.value = "Recording #{now.toLocaleDateString()} #{now.toLocaleTimeString()}"

    # Show preview
    previewTarget.classList.remove('hidden')

    # Start transcription
    transcribe(@audioBlob)
  end

  async def transcribe(blob)
    return unless @transcriber

    transcribingTarget.classList.remove('hidden')
    transcriptTarget.value = ""
    transcriptTarget.placeholder = "Transcribing..."

    begin
      # Create object URL for read_audio
      audioUrl = URL.createObjectURL(blob)

      # Convert audio to Float32Array at 16kHz (Whisper's expected format)
      audioData = await read_audio(audioUrl, 16000)

      # Clean up object URL
      URL.revokeObjectURL(audioUrl)

      # Transcribe
      result = await @transcriber.call(audioData)

      transcriptTarget.value = result.text.strip()
      transcriptTarget.placeholder = "Transcription will appear here..."

    rescue => error
      console.error("Transcription failed:", error)
      transcriptTarget.placeholder = "Transcription failed. You can type manually."
    ensure
      transcribingTarget.classList.add('hidden')
    end
  end

  async def save(event)
    event.preventDefault()

    return unless @audioBlob

    begin
      # Create clip record first
      clip = await Clip.create(
        name: nameTarget.value || "Untitled Recording",
        transcript: transcriptTarget.value,
        duration: parseFloat(durationTarget.value) || @audioDuration
      )

      # Attach audio via Active Storage
      extension = @audioBlob.type.include?('webm') ? 'webm' : 'm4a'
      await clip.audio.attach(@audioBlob,
        filename: "#{clip.name.gsub(/[^a-z0-9]/i, '_')}.#{extension}",
        content_type: @audioBlob.type
      )

      console.log("Clip saved with audio attachment:", clip.id)

      # Replace the initially-broadcast clip (which had no audio) with the full version
      await clip.broadcast_replace_to("clips")

      resetUI()

    rescue => error
      console.error("Failed to save clip:", error)
      statusTarget.textContent = "Failed to save clip. Please try again."
      statusTarget.classList.remove('bg-green-50', 'text-green-800')
      statusTarget.classList.add('bg-red-50', 'text-red-800')
    end
  end

  def discard
    resetUI()
  end

  def resetUI
    # Revoke object URL
    URL.revokeObjectURL(audioTarget.src) if audioTarget.src

    # Clear stored blob
    @audioBlob = nil
    @audioDuration = nil

    # Clear form
    audioTarget.src = ""
    audioDataTarget.value = ""
    durationTarget.value = ""
    nameTarget.value = ""
    transcriptTarget.value = ""

    # Hide preview
    previewTarget.classList.add('hidden')

    # Reset status
    statusTarget.textContent = "Ready to record"
    statusTarget.classList.remove('bg-red-50', 'text-red-800')
    statusTarget.classList.add('bg-green-50', 'text-green-800')
  end
end
