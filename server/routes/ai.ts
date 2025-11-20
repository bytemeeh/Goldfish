
import { Router } from 'express';
import multer from 'multer';
import { db } from "../../db";
import { contacts, locations, type Contact, type Location } from "../../db/schema";
import { eq, or, ilike } from 'drizzle-orm';
import { transcribeAudio, extractContactInfo, parseRelationshipCommand } from '../lib/openai';
import { log } from '../vite';

const router = Router();

// Configure multer for audio file uploads
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit
  },
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('audio/')) {
      cb(null, true);
    } else {
      cb(new Error('Only audio files are allowed') as any, false);
    }
  }
});

// POST /api/ai/transcribe - Handle voice input and process it
router.post('/transcribe', upload.single('audio'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No audio file provided' });
    }

    const mode = req.body.mode || 'contact';
    const audioBuffer = req.file.buffer;

    log(`AI: Processing ${mode} mode audio(${audioBuffer.length} bytes)`);

    // Transcribe the audio
    const transcription = await transcribeAudio(audioBuffer);
    log(`AI: Transcribed: "${transcription}"`);

    let result = null;

    if (mode === 'contact') {
      // Extract contact information
      const contactData = await extractContactInfo(transcription);
      log(`AI: Extracted contact data: ${JSON.stringify(contactData)}`);

      // Find parent contact if specified
      let parentId = null;
      if (contactData.parentName) {
        const parentContact = await db.query.contacts.findFirst({
          where: ilike(contacts.name, `% ${contactData.parentName}% `)
        });
        if (parentContact) {
          parentId = parentContact.id;
        }
      }

      // Create the contact
      const insertedContacts = await db.insert(contacts).values({
        name: contactData.name,
        phone: contactData.phone,
        email: contactData.email,
        birthday: contactData.birthday,
        notes: contactData.notes,
        relationshipType: contactData.relationshipType,
        parentId: parentId,
        color: contactData.color || 'blue',
        isMe: false
      }).returning() as any;
      const newContact = insertedContacts[0];

      result = {
        type: 'contact_created',
        contact: newContact
      };

    } else if (mode === 'relationship') {
      // Get all contacts for relationship parsing
      const allContacts = await db.query.contacts.findMany();

      // Parse relationship command
      const relationshipCommand = await parseRelationshipCommand(transcription, allContacts);
      log(`AI: Parsed relationship command: ${JSON.stringify(relationshipCommand)}`);

      // Find source and target contacts
      const sourceContact = allContacts.find(c =>
        c.name.toLowerCase().includes(relationshipCommand.sourceName.toLowerCase())
      );
      const targetContact = allContacts.find(c =>
        c.name.toLowerCase().includes(relationshipCommand.targetName.toLowerCase())
      );

      if (!sourceContact || !targetContact) {
        return res.status(400).json({
          error: 'Could not find one or both contacts mentioned in the command',
          transcription
        });
      }

      // Execute relationship command
      if (relationshipCommand.action === 'connect' || relationshipCommand.action === 'change') {
        await db.update(contacts)
          .set({
            parentId: targetContact.id,
            relationshipType: relationshipCommand.relationshipType
          })
          .where(eq(contacts.id, sourceContact.id));
      } else if (relationshipCommand.action === 'disconnect') {
        await db.update(contacts)
          .set({
            parentId: null,
            relationshipType: null
          })
          .where(eq(contacts.id, sourceContact.id));
      }

      result = {
        type: 'relationship_updated',
        command: relationshipCommand,
        sourceContact: sourceContact,
        targetContact: targetContact
      };
    }

    res.json({
      transcription,
      result
    });

  } catch (error) {
    console.error('AI transcription error:', error);
    res.status(500).json({
      error: 'Failed to process audio',
      details: error instanceof Error ? error.message : 'Unknown error'
    });
  }
});

// GET /api/ai/status - Check if AI is available
router.get('/status', (req, res) => {
  res.json({
    available: !!process.env.OPENAI_API_KEY,
    features: ['voice_transcription', 'contact_extraction', 'relationship_parsing']
  });
});

export default router;