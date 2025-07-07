import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { VoiceInput } from './VoiceInput';
import { useToast } from '@/hooks/use-toast';
import { useQueryClient } from '@tanstack/react-query';
import { MessageCircle, Users, Sparkles } from 'lucide-react';

interface RelationshipManagerProps {
  className?: string;
}

export function RelationshipManager({ className }: RelationshipManagerProps) {
  const [isProcessing, setIsProcessing] = useState(false);
  const [transcription, setTranscription] = useState<string>("");
  const [lastCommand, setLastCommand] = useState<any>(null);
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const handleVoiceTranscription = (text: string) => {
    setTranscription(text);
  };

  const handleVoiceProcessingComplete = (result: any) => {
    if (result.type === 'relationship_updated') {
      setLastCommand(result.command);
      
      // Refresh the contacts data to show the updated relationships
      queryClient.invalidateQueries({ queryKey: ['/api/contacts'] });
      
      const { command, sourceContact, targetContact } = result;
      
      let description = '';
      if (command.action === 'connect') {
        description = `${sourceContact.name} is now connected as ${targetContact.name}'s ${command.relationshipType}`;
      } else if (command.action === 'disconnect') {
        description = `${sourceContact.name} has been disconnected from ${targetContact.name}`;
      } else if (command.action === 'change') {
        description = `${sourceContact.name}'s relationship to ${targetContact.name} has been changed to ${command.relationshipType}`;
      }
      
      toast({
        title: "Relationship updated",
        description: description
      });
    }
    setIsProcessing(false);
  };

  const handleError = (error: string) => {
    toast({
      title: "Command failed",
      description: error,
      variant: "destructive"
    });
    setIsProcessing(false);
  };

  return (
    <Card className={className}>
      <CardHeader className="pb-3">
        <CardTitle className="flex items-center space-x-2 text-base">
          <Users className="h-5 w-5 text-blue-600" />
          <span>Relationship Manager</span>
          <Sparkles className="h-4 w-4 text-purple-500" />
        </CardTitle>
        <CardDescription className="text-sm">
          Use voice commands to manage contact relationships
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="text-sm text-gray-600">
            Examples: "Make Sarah John's daughter", "Connect Mike as Tom's co-worker"
          </div>
          <VoiceInput 
            onTranscription={handleVoiceTranscription}
            onProcessingComplete={handleVoiceProcessingComplete}
            placeholder="Speak relationship command..."
            mode="relationship"
            isProcessing={isProcessing}
            className="text-xs"
          />
        </div>
        
        {transcription && (
          <div className="bg-gray-50 p-3 rounded-lg border">
            <div className="text-xs font-medium text-gray-700 mb-1">Voice Command:</div>
            <div className="text-sm text-gray-900">"{transcription}"</div>
          </div>
        )}
        
        {lastCommand && (
          <div className="bg-green-50 p-3 rounded-lg border border-green-200">
            <div className="text-xs font-medium text-green-700 mb-1">Last Action:</div>
            <div className="text-sm text-green-900 capitalize">
              {lastCommand.action}ed {lastCommand.sourceName} {lastCommand.action === 'disconnect' ? 'from' : 'as'} {lastCommand.targetName}'s {lastCommand.relationshipType}
            </div>
          </div>
        )}
        
        <div className="text-xs text-gray-500 space-y-1">
          <div><strong>Available commands:</strong></div>
          <div>• "Make [Person A] [Person B]'s [relationship]"</div>
          <div>• "Connect [Person A] as [Person B]'s [relationship]"</div>
          <div>• "Change [Person A] from [old] to [new] of [Person B]"</div>
          <div>• "Disconnect [Person A] from [Person B]"</div>
        </div>
      </CardContent>
    </Card>
  );
}