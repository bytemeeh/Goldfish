import { useState, useRef, ChangeEvent } from 'react';
import { Camera, Upload, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { PermissionPrimingDialog } from '@/components/ui/PermissionPrimingDialog';

interface PhotoUploadProps {
  currentPhoto?: string;
  onPhotoChange: (photo: string | null) => void;
  className?: string;
}

export function PhotoUpload({ currentPhoto, onPhotoChange, className = "" }: PhotoUploadProps) {
  const [preview, setPreview] = useState<string | null>(currentPhoto || null);
  const [showPermissionDialog, setShowPermissionDialog] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleFileSelect = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    // Check file size (limit to 5MB)
    if (file.size > 5 * 1024 * 1024) {
      alert('Photo must be smaller than 5MB');
      return;
    }

    // Check file type
    if (!file.type.startsWith('image/')) {
      alert('Please select an image file');
      return;
    }

    const reader = new FileReader();
    reader.onload = (e) => {
      const base64 = e.target?.result as string;
      setPreview(base64);
      onPhotoChange(base64);
    };
    reader.readAsDataURL(file);
  };

  const handleRemovePhoto = () => {
    setPreview(null);
    onPhotoChange(null);
    if (fileInputRef.current) {
      fileInputRef.current.value = '';
    }
  };

  const handleUploadClick = () => {
    setShowPermissionDialog(true);
  };

  const handlePermissionContinue = () => {
    setShowPermissionDialog(false);
    fileInputRef.current?.click();
  };

  return (
    <div className={`flex items-center gap-3 ${className}`}>
      {/* Photo Preview Circle */}
      <div className="relative">
        <div className="w-16 h-16 rounded-full border-2 border-blue-500 bg-blue-50 flex items-center justify-center overflow-hidden">
          {preview ? (
            <img
              src={preview}
              alt="Profile"
              className="w-full h-full object-cover"
            />
          ) : (
            <Camera className="w-6 h-6 text-blue-500" />
          )}
        </div>

        {/* Remove Button */}
        {preview && (
          <button
            onClick={handleRemovePhoto}
            className="absolute -top-1 -right-1 w-5 h-5 bg-red-500 rounded-full flex items-center justify-center hover:bg-red-600 transition-colors"
          >
            <X className="w-3 h-3 text-white" />
          </button>
        )}
      </div>

      {/* Upload Button */}
      <Button
        type="button"
        variant="outline"
        size="sm"
        onClick={handleUploadClick}
        className="flex items-center gap-2"
      >
        <Upload className="w-4 h-4" />
        {preview ? 'Change Photo' : 'Add Photo'}
      </Button>

      {/* Hidden File Input */}
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        onChange={handleFileSelect}
        className="hidden"
      />

      <PermissionPrimingDialog
        open={showPermissionDialog}
        onOpenChange={setShowPermissionDialog}
        permissionType="photo"
        onContinue={handlePermissionContinue}
        onCancel={() => setShowPermissionDialog(false)}
      />
    </div>
  );
}