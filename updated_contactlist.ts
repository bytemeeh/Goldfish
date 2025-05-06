// This is a helper file containing updates we want to make
// We'll use it to create a simple script to update all ContactCard instances

// Make sure we update all contact cards with isSelected prop
const updateContactCards = () => {
  // Find all places in the file where we need to insert isSelected prop
  
  // In the first instance
  const personalCardLocation = "relationshipLevel={0}";
  const personalCardReplacement = "relationshipLevel={0}\n                      isSelected={selectedContactId === personalHierarchy.id}";

  // For all contacts
  const contactCardPattern = "relationshipLevel={getRelationshipLevel(contact)}";
  const contactCardReplacement = "relationshipLevel={getRelationshipLevel(contact)}\n                                  isSelected={selectedContactId === contact.id}";
}
