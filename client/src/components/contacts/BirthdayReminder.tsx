import { useState, useEffect } from 'react';
import { differenceInDays, format } from 'date-fns';
import { AlertCircle, Cake, X } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { Contact } from '@/lib/types';
import { Button } from '@/components/ui/button';

interface BirthdayReminderProps {
  contacts: Contact[];
}

interface BirthdayNotification {
  contact: Contact;
  daysUntil: number;
  isToday: boolean;
}

export function BirthdayReminder({ contacts }: BirthdayReminderProps) {
  const [notifications, setNotifications] = useState<BirthdayNotification[]>([]);
  const [dismissed, setDismissed] = useState<Set<number>>(new Set());
  const [showReminders, setShowReminders] = useState(true);

  // Check for birthdays every day (on component mount and when contacts change)
  useEffect(() => {
    checkForBirthdays();
    // Set up daily check
    const interval = setInterval(checkForBirthdays, 86400000); // 24 hours
    return () => clearInterval(interval);
  }, [contacts]);

  // Load dismissed notifications from localStorage on mount
  useEffect(() => {
    const today = new Date().toISOString().split('T')[0];
    const savedDismissed = localStorage.getItem(`birthday_dismissed_${today}`);
    if (savedDismissed) {
      setDismissed(new Set(JSON.parse(savedDismissed)));
    }
  }, []);

  const checkForBirthdays = () => {
    const today = new Date();
    const currentYear = today.getFullYear();
    const birthdayNotifications: BirthdayNotification[] = [];

    contacts.forEach(contact => {
      if (!contact.birthday) return;

      // Get date parts without time to avoid timezone issues
      const contactBirthday = new Date(contact.birthday);

      // Create this year's birthday
      const thisYearBirthday = new Date(
        currentYear,
        contactBirthday.getMonth(),
        contactBirthday.getDate()
      );

      // Calculate days until birthday
      const daysUntil = differenceInDays(thisYearBirthday, today);

      // Check if today is birthday or 7 days before
      const isToday = daysUntil === 0;
      const isWeekBefore = daysUntil === 7;

      if ((isToday || isWeekBefore) && !dismissed.has(contact.id)) {
        birthdayNotifications.push({
          contact,
          daysUntil,
          isToday
        });
      }
    });

    setNotifications(birthdayNotifications);
  };

  const dismissNotification = (contactId: number) => {
    // Create a new Set with existing dismissed IDs
    const newDismissed = new Set(dismissed);
    newDismissed.add(contactId);
    setDismissed(newDismissed);

    // Save to localStorage (just for today)
    const today = new Date().toISOString().split('T')[0];
    localStorage.setItem(
      `birthday_dismissed_${today}`,
      JSON.stringify([...newDismissed])
    );
  };

  const dismissAll = () => {
    const allIds = notifications.map(notification => notification.contact.id);
    const newDismissed = new Set([...dismissed, ...allIds]);
    setDismissed(newDismissed);

    // Save to localStorage
    const today = new Date().toISOString().split('T')[0];
    localStorage.setItem(
      `birthday_dismissed_${today}`,
      JSON.stringify([...newDismissed])
    );

    // Hide the reminder panel
    setShowReminders(false);
  };

  // If no notifications or all dismissed, don't render anything
  if (notifications.length === 0 || !showReminders) {
    return null;
  }

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -20 }}
        className="fixed top-4 right-4 z-50 max-w-sm w-full"
      >
        <div className="bg-card border rounded-lg shadow-lg overflow-hidden">
          <div className="bg-primary/10 px-4 py-2 flex justify-between items-center">
            <div className="flex items-center text-sm font-medium text-primary">
              <Cake className="h-4 w-4 mr-2" />
              Birthday Reminders
            </div>
            <Button 
              variant="ghost" 
              size="sm" 
              className="h-6 w-6 p-0" 
              onClick={dismissAll}
            >
              <X className="h-4 w-4" />
            </Button>
          </div>
          <div className="p-3 max-h-[300px] overflow-y-auto">
            {notifications.map(({ contact, daysUntil, isToday }) => (
              <motion.div
                key={contact.id}
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: 10 }}
                className="flex items-start p-2 mb-2 bg-background/50 rounded border"
              >
                <div className="mr-2 mt-0.5">
                  {isToday ? (
                    <Cake className="h-5 w-5 text-primary" />
                  ) : (
                    <AlertCircle className="h-5 w-5 text-amber-500" />
                  )}
                </div>
                <div className="flex-1">
                  <p className="text-sm font-medium">{contact.name}</p>
                  <p className="text-xs text-muted-foreground">
                    {isToday
                      ? "Birthday is today! 🎂"
                      : `Birthday in ${daysUntil} days (${format(
                          new Date(contact.birthday!),
                          "MMMM d"
                        )})`}
                  </p>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-6 w-6 p-0 ml-2"
                  onClick={() => dismissNotification(contact.id)}
                >
                  <X className="h-3 w-3" />
                </Button>
              </motion.div>
            ))}
          </div>
          <div className="bg-muted/30 px-3 py-2 text-center">
            <Button 
              variant="outline" 
              size="sm" 
              className="text-xs h-7"
              onClick={dismissAll}
            >
              Dismiss All
            </Button>
          </div>
        </div>
      </motion.div>
    </AnimatePresence>
  );
}
