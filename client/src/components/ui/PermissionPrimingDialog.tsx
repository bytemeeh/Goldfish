import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { MapPin, Camera, Shield } from "lucide-react";

export type PermissionType = "location" | "camera" | "photo";

interface PermissionPrimingDialogProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    permissionType: PermissionType;
    onContinue: () => void;
    onCancel: () => void;
}

export function PermissionPrimingDialog({
    open,
    onOpenChange,
    permissionType,
    onContinue,
    onCancel,
}: PermissionPrimingDialogProps) {
    const getContent = () => {
        switch (permissionType) {
            case "location":
                return {
                    icon: <MapPin className="w-10 h-10 text-blue-500" />,
                    title: "Enable Location Access",
                    description:
                        "Goldfish uses your location to help you find contacts nearby and organize your network geographically. We only access your location when you ask us to.",
                };
            case "camera":
            case "photo":
                return {
                    icon: <Camera className="w-10 h-10 text-blue-500" />,
                    title: "Access Photos & Camera",
                    description:
                        "Goldfish needs access to your photos to let you add profile pictures to your contacts. This helps you recognize people in your network instantly.",
                };
            default:
                return {
                    icon: <Shield className="w-10 h-10 text-blue-500" />,
                    title: "Permission Request",
                    description: "Goldfish needs access to this feature to provide a better experience.",
                };
        }
    };

    const content = getContent();

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent className="sm:max-w-[425px]">
                <DialogHeader className="flex flex-col items-center text-center gap-4 pt-4">
                    <div className="w-20 h-20 bg-blue-50 rounded-full flex items-center justify-center mb-2">
                        {content.icon}
                    </div>
                    <DialogTitle className="text-xl">{content.title}</DialogTitle>
                    <DialogDescription className="text-center pt-2">
                        {content.description}
                    </DialogDescription>
                </DialogHeader>
                <DialogFooter className="flex-col sm:flex-col gap-2 mt-4">
                    <Button onClick={onContinue} className="w-full">
                        Continue
                    </Button>
                    <Button variant="ghost" onClick={onCancel} className="w-full">
                        Not Now
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
}
