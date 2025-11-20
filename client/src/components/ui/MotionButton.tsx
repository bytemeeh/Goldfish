import { motion } from "framer-motion";
import { Button, ButtonProps } from "@/components/ui/button";
import { forwardRef } from "react";

export const MotionButton = motion(
    forwardRef<HTMLButtonElement, ButtonProps>((props, ref) => (
        <Button ref={ref} {...props} />
    ))
);

export const tapAnimation = {
    scale: 0.95,
    transition: { duration: 0.1 }
};
