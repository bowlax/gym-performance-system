import { forwardRef, type InputHTMLAttributes, type ReactNode } from "react";
import { cn } from "@/lib/utils";

export interface FormFieldProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string;
  hint?: string;
  trailing?: ReactNode;
  numeric?: boolean;
}

/**
 * FormField — iOS-style stacked label + rounded input, with a wolf-blue
 * focus ring. Set `numeric` for weight/rep entry to swap in tabular figures.
 */
export const FormField = forwardRef<HTMLInputElement, FormFieldProps>(
  ({ label, hint, trailing, numeric, className, id, ...props }, ref) => {
    const inputId = id ?? `field-${label.replace(/\s+/g, "-").toLowerCase()}`;
    return (
      <div className="flex flex-col gap-1.5">
        <label
          htmlFor={inputId}
          className="text-sm font-medium text-foreground"
        >
          {label}
        </label>
        <div
          className={cn(
            "flex items-center gap-2 rounded-[10px] border border-input bg-surface px-3.5 h-12",
            "transition-shadow focus-within:border-primary focus-within:ring-4 focus-within:ring-primary/15",
          )}
        >
          <input
            id={inputId}
            ref={ref}
            className={cn(
              "peer h-full w-full bg-transparent text-base text-foreground outline-none placeholder:text-muted-foreground",
              numeric && "font-numeric text-lg",
              className,
            )}
            {...props}
          />
          {trailing && (
            <span className="shrink-0 text-sm font-medium text-muted-foreground">
              {trailing}
            </span>
          )}
        </div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </div>
    );
  },
);
FormField.displayName = "FormField";