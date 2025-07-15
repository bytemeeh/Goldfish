import React, { useState, useRef, useCallback } from 'react';
import { Button } from '@/components/ui/button';
import { Mic, MicOff, Loader2, MessageCircle } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useToast } from '@/hooks/use-toast';

interface VoiceInputProps {
  onTranscription: (text: string) => void;
  onProcessingComplete?: (result: any) => void;
  placeholder?: string;
  mode?: 'contact' | 'relationship';
  isProcessing?: boolean;
  className?: string;
}

export function VoiceInput({ 
  onTranscription, 
  onProcessingComplete,
  placeholder = "Click to speak...",
  mode = 'contact',
  isProcessing = false,
  className 
}: VoiceInputProps) {
  const [isRecording, setIsRecording] = useState(false);
  const [isTranscribing, setIsTranscribing] = useState(false);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const { toast } = useToast();

  const startRecording = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      
      const mediaRecorder = new MediaRecorder(stream, {
        mimeType: 'audio/webm;codecs=opus'
      });
      
      mediaRecorderRef.current = mediaRecorder;
      audioChunksRef.current = [];

      mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          audioChunksRef.current.push(event.data);
        }
      };

      mediaRecorder.onstop = async () => {
        const audioBlob = new Blob(audioChunksRef.current, { type: 'audio/webm' });
        await transcribeAudio(audioBlob);
        
        // Clean up
        stream.getTracks().forEach(track => track.stop());
      };

      mediaRecorder.start();
      setIsRecording(true);
      
      toast({
        title: "Recording started",
        description: mode === 'contact' ? "Speak the contact details..." : "Speak the relationship command..."
      });
    } catch (error) {
      console.error('Error starting recording:', error);
      toast({
        title: "Recording failed",
        description: "Please allow microphone access and try again.",
        variant: "destructive"
      });
    }
  }, [mode, toast]);

  const stopRecording = useCallback(() => {
    if (mediaRecorderRef.current && isRecording) {
      mediaRecorderRef.current.stop();
      setIsRecording(false);
      setIsTranscribing(true);
    }
  }, [isRecording]);

  const transcribeAudio = useCallback(async (audioBlob: Blob) => {
    try {
      const formData = new FormData();
      formData.append('audio', audioBlob, 'recording.webm');
      formData.append('mode', mode);

      const response = await fetch('/api/ai/transcribe', {
        method: 'POST',
        body: formData
      });

      if (!response.ok) {
        throw new Error('Transcription failed');
      }

      const data = await response.json();
      
      if (data.transcription) {
        onTranscription(data.transcription);
        
        if (data.result && onProcessingComplete) {
          onProcessingComplete(data.result);
        }
        
        toast({
          title: "Voice processed",
          description: mode === 'contact' ? "Contact details extracted!" : "Relationship command processed!"
        });
      }
    } catch (error) {
      console.error('Error transcribing audio:', error);
      toast({
        title: "Processing failed",
        description: "Could not process the audio. Please try again.",
        variant: "destructive"
      });
    } finally {
      setIsTranscribing(false);
    }
  }, [mode, onTranscription, onProcessingComplete, toast]);

  const handleClick = useCallback(() => {
    if (isRecording) {
      stopRecording();
    } else if (!isTranscribing && !isProcessing) {
      startRecording();
    }
  }, [isRecording, isTranscribing, isProcessing, startRecording, stopRecording]);

  const isLoading = isTranscribing || isProcessing;
  const isActive = isRecording || isLoading;

  return (
    <Button
      onClick={handleClick}
      disabled={isLoading}
      variant={isActive ? "default" : "outline"}
      size="sm"
      className={cn(
        "relative overflow-hidden transition-all duration-200",
        isRecording && "bg-red-500 hover:bg-red-600 animate-pulse",
        isLoading && "bg-blue-500 hover:bg-blue-600",
        className
      )}
    >
      {isLoading ? (
        <>
          <Loader2 className="h-4 w-4 mr-2 animate-spin" />
          {isTranscribing ? "Processing..." : "Analyzing..."}
        </>
      ) : isRecording ? (
        <>
          <MicOff className="h-4 w-4 mr-2" />
          Stop Recording
        </>
      ) : (
        <>
          {mode === 'contact' ? (
            <Mic className="h-4 w-4 mr-2" />
          ) : (
            <MessageCircle className="h-4 w-4 mr-2" />
          )}
          {placeholder || (mode === 'contact' ? 'Add by Voice' : 'Voice Command')}
        </>
      )}
    </Button>
  );
}