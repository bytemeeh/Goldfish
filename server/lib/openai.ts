import OpenAI from "openai";
import { Contact, RelationshipType } from "@db/schema";

// the newest OpenAI model is "gpt-4o" which was released May 13, 2024. do not change this unless explicitly requested by the user
let openai: OpenAI | null = null;

function getOpenAIClient(): OpenAI {
  if (!openai) {
    if (!process.env.OPENAI_API_KEY) {
      throw new Error('OpenAI API key is not configured');
    }
    openai = new OpenAI({ 
      apiKey: process.env.OPENAI_API_KEY 
    });
  }
  return openai;
}

export interface ExtractedContactData {
  name: string;
  phone?: string;
  email?: string;
  birthday?: string;
  notes?: string;
  relationshipType?: RelationshipType;
  parentName?: string;
  color?: string;
}

export interface RelationshipCommand {
  action: 'connect' | 'disconnect' | 'change';
  sourceName: string;
  targetName: string;
  relationshipType: RelationshipType;
  direction?: 'to' | 'from';
}

export async function transcribeAudio(audioBuffer: Buffer): Promise<string> {
  try {
    const client = getOpenAIClient();
    const file = new File([audioBuffer], 'audio.webm', { type: 'audio/webm' });
    
    const transcription = await client.audio.transcriptions.create({
      file: file,
      model: "whisper-1",
      response_format: "text",
      language: "en"
    });

    return transcription.trim();
  } catch (error) {
    console.error('Transcription error:', error);
    throw new Error('Failed to transcribe audio');
  }
}

export async function extractContactInfo(transcription: string): Promise<ExtractedContactData> {
  try {
    const client = getOpenAIClient();
    const prompt = `Extract contact information from this spoken text and return JSON. 
    
Available relationship types: sibling, mother, father, brother, friend, child, co-worker, spouse, boyfriend/girlfriend

Text: "${transcription}"

Return JSON with these fields (only include fields that are clearly mentioned):
- name (required)
- phone (format: include country code if mentioned)
- email
- birthday (format: YYYY-MM-DD if date is mentioned)
- notes (any additional information)
- relationshipType (from the list above)
- parentName (if this person is related to someone else)
- color (if a color is mentioned for the card)

Example: "Add Sarah Johnson, she's John's daughter, phone is 555-0123, email sarah@email.com, birthday March 15th 1995, make her card green"
Would return: {"name": "Sarah Johnson", "phone": "555-0123", "email": "sarah@email.com", "birthday": "1995-03-15", "relationshipType": "child", "parentName": "John", "color": "green"}`;

    const response = await client.chat.completions.create({
      model: "gpt-4o",
      messages: [
        {
          role: "system",
          content: "You are a contact information extraction expert. Extract structured contact data from natural speech and return only valid JSON."
        },
        {
          role: "user",
          content: prompt
        }
      ],
      response_format: { type: "json_object" },
      temperature: 0.1
    });

    const result = JSON.parse(response.choices[0].message.content || '{}');
    
    // Validate required fields
    if (!result.name) {
      throw new Error('Contact name is required');
    }

    return result as ExtractedContactData;
  } catch (error) {
    console.error('Contact extraction error:', error);
    throw new Error('Failed to extract contact information');
  }
}

export async function parseRelationshipCommand(
  transcription: string, 
  existingContacts: Contact[]
): Promise<RelationshipCommand> {
  try {
    const client = getOpenAIClient();
    const contactNames = existingContacts.map(c => c.name).join(', ');
    
    const prompt = `Parse this relationship command and return JSON.

Available relationship types: sibling, mother, father, brother, friend, child, co-worker, spouse, boyfriend/girlfriend
Known contacts: ${contactNames}

Command: "${transcription}"

Return JSON with:
- action: "connect" | "disconnect" | "change"
- sourceName: first person's name
- targetName: second person's name  
- relationshipType: the relationship type
- direction: "to" | "from" (who is the parent/child)

Examples:
"Make Sarah John's daughter" → {"action": "connect", "sourceName": "Sarah", "targetName": "John", "relationshipType": "child", "direction": "to"}
"Connect Mike as Tom's co-worker" → {"action": "connect", "sourceName": "Mike", "targetName": "Tom", "relationshipType": "co-worker", "direction": "to"}
"Change Lisa from friend to spouse of David" → {"action": "change", "sourceName": "Lisa", "targetName": "David", "relationshipType": "spouse", "direction": "to"}
"Disconnect Amy from being Bob's sister" → {"action": "disconnect", "sourceName": "Amy", "targetName": "Bob", "relationshipType": "sibling", "direction": "to"}`;

    const response = await client.chat.completions.create({
      model: "gpt-4o",
      messages: [
        {
          role: "system",
          content: "You are a relationship command parser. Parse natural language commands about contact relationships and return structured JSON."
        },
        {
          role: "user",
          content: prompt
        }
      ],
      response_format: { type: "json_object" },
      temperature: 0.1
    });

    const result = JSON.parse(response.choices[0].message.content || '{}');
    
    // Validate required fields
    if (!result.action || !result.sourceName || !result.targetName) {
      throw new Error('Invalid relationship command format');
    }

    return result as RelationshipCommand;
  } catch (error) {
    console.error('Relationship parsing error:', error);
    throw new Error('Failed to parse relationship command');
  }
}