export const CONTACT_COLORS = {
  blue: {
    name: 'Blue',
    bg: 'bg-blue-50',
    border: 'border-blue-300',
    text: 'text-blue-900',
    ring: 'ring-blue-400',
    gradient: 'from-blue-400 to-blue-600',
    hex: '#3b82f6'
  },
  green: {
    name: 'Green',
    bg: 'bg-green-50',
    border: 'border-green-300',
    text: 'text-green-900',
    ring: 'ring-green-400',
    gradient: 'from-green-400 to-green-600',
    hex: '#10b981'
  },
  purple: {
    name: 'Purple',
    bg: 'bg-purple-50',
    border: 'border-purple-300',
    text: 'text-purple-900',
    ring: 'ring-purple-400',
    gradient: 'from-purple-400 to-purple-600',
    hex: '#a855f7'
  },
  pink: {
    name: 'Pink',
    bg: 'bg-pink-50',
    border: 'border-pink-300',
    text: 'text-pink-900',
    ring: 'ring-pink-400',
    gradient: 'from-pink-400 to-pink-600',
    hex: '#ec4899'
  },
  orange: {
    name: 'Orange',
    bg: 'bg-orange-50',
    border: 'border-orange-300',
    text: 'text-orange-900',
    ring: 'ring-orange-400',
    gradient: 'from-orange-400 to-orange-600',
    hex: '#f97316'
  },
  red: {
    name: 'Red',
    bg: 'bg-red-50',
    border: 'border-red-300',
    text: 'text-red-900',
    ring: 'ring-red-400',
    gradient: 'from-red-400 to-red-600',
    hex: '#ef4444'
  },
  indigo: {
    name: 'Indigo',
    bg: 'bg-indigo-50',
    border: 'border-indigo-300',
    text: 'text-indigo-900',
    ring: 'ring-indigo-400',
    gradient: 'from-indigo-400 to-indigo-600',
    hex: '#6366f1'
  },
  yellow: {
    name: 'Yellow',
    bg: 'bg-yellow-50',
    border: 'border-yellow-300',
    text: 'text-yellow-900',
    ring: 'ring-yellow-400',
    gradient: 'from-yellow-400 to-yellow-600',
    hex: '#eab308'
  },
  teal: {
    name: 'Teal',
    bg: 'bg-teal-50',
    border: 'border-teal-300',
    text: 'text-teal-900',
    ring: 'ring-teal-400',
    gradient: 'from-teal-400 to-teal-600',
    hex: '#14b8a6'
  },
  emerald: {
    name: 'Emerald',
    bg: 'bg-emerald-50',
    border: 'border-emerald-300',
    text: 'text-emerald-900',
    ring: 'ring-emerald-400',
    gradient: 'from-emerald-400 to-emerald-600',
    hex: '#10b981'
  }
} as const;

export type ContactColor = keyof typeof CONTACT_COLORS;

export const getContactColorClasses = (color: ContactColor | string = 'blue') => {
  const colorKey = color as ContactColor;
  return CONTACT_COLORS[colorKey] || CONTACT_COLORS.blue;
};

export const getContactColorOptions = () => {
  return Object.entries(CONTACT_COLORS).map(([key, value]) => ({
    value: key,
    label: value.name,
    color: value.hex
  }));
};