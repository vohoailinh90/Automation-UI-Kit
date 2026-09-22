import { Command as CommandPrimitive } from "cmdk"
import { SearchIcon } from "lucide-react"
import * as React from "react"

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { cn } from "@/lib/utils"

function Command({ className, ...props }: React.ComponentProps<typeof CommandPrimitive>) {
  return (
    <CommandPrimitive
      data-slot="command"
      className={cn(
        "flex size-full flex-col overflow-hidden rounded-md bg-popover text-popover-foreground",
        className,
      )}
      {...props}
    />
  )
}

/**
 * Bảng lệnh dạng dialog (kiểu ⌘K).
 *
 * `title`/`description` bắt buộc phải có và được ẩn bằng `sr-only`: Radix Dialog
 * cần tên truy cập được, thiếu thì screen reader chỉ đọc được "dialog" trống.
 *
 * `trigger` nên truyền vào kể cả khi dialog đã được điều khiển bằng state: lúc
 * đóng, Radix trả focus về đúng `DialogTrigger`. Không có nó thì focus rơi về
 * `<body>`, và người dùng bàn phím phải Tab lại từ đầu trang.
 */
function CommandDialog({
  title,
  description,
  children,
  className,
  trigger,
  ...props
}: React.ComponentProps<typeof Dialog> & {
  title: string
  description: string
  className?: string
  trigger?: React.ReactNode
}) {
  return (
    <Dialog {...props}>
      {trigger && <DialogTrigger asChild>{trigger}</DialogTrigger>}
      <DialogContent className={cn("overflow-hidden p-0", className)} showCloseButton={false}>
        <DialogTitle className="sr-only">{title}</DialogTitle>
        <DialogDescription className="sr-only">{description}</DialogDescription>
        <Command className="[&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:py-1.5 [&_[cmdk-group-heading]]:text-xs [&_[cmdk-group-heading]]:font-medium [&_[cmdk-group-heading]]:text-muted-foreground">
          {children}
        </Command>
      </DialogContent>
    </Dialog>
  )
}

function CommandInput({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Input>) {
  return (
    <div className="flex items-center gap-2 border-b px-3">
      <SearchIcon className="size-4 shrink-0 opacity-50" aria-hidden />
      <CommandPrimitive.Input
        data-slot="command-input"
        className={cn(
          "flex h-11 w-full bg-transparent py-3 text-sm outline-hidden placeholder:text-muted-foreground disabled:cursor-not-allowed disabled:opacity-50",
          className,
        )}
        {...props}
      />
    </div>
  )
}

function CommandList({ className, ...props }: React.ComponentProps<typeof CommandPrimitive.List>) {
  return (
    <CommandPrimitive.List
      data-slot="command-list"
      className={cn("max-h-72 scroll-py-1 overflow-y-auto overflow-x-hidden", className)}
      {...props}
    />
  )
}

function CommandEmpty(props: React.ComponentProps<typeof CommandPrimitive.Empty>) {
  return (
    <CommandPrimitive.Empty
      data-slot="command-empty"
      className="py-6 text-center text-sm text-muted-foreground"
      {...props}
    />
  )
}

function CommandGroup({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Group>) {
  return (
    <CommandPrimitive.Group
      data-slot="command-group"
      className={cn("overflow-hidden p-1 text-foreground", className)}
      {...props}
    />
  )
}

function CommandSeparator({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Separator>) {
  return (
    <CommandPrimitive.Separator
      data-slot="command-separator"
      className={cn("-mx-1 h-px bg-border", className)}
      {...props}
    />
  )
}

function CommandItem({ className, ...props }: React.ComponentProps<typeof CommandPrimitive.Item>) {
  return (
    <CommandPrimitive.Item
      data-slot="command-item"
      className={cn(
        "relative flex cursor-default select-none items-center gap-2 rounded-sm px-2 py-2 text-sm outline-hidden",
        "data-[selected=true]:bg-accent data-[selected=true]:text-accent-foreground",
        "data-[disabled=true]:pointer-events-none data-[disabled=true]:opacity-50",
        className,
      )}
      {...props}
    />
  )
}

function CommandShortcut({ className, ...props }: React.ComponentProps<"kbd">) {
  return (
    <kbd
      data-slot="command-shortcut"
      className={cn(
        "ml-auto rounded border bg-muted px-1.5 py-0.5 font-sans text-[10px] font-medium tracking-widest text-muted-foreground",
        className,
      )}
      {...props}
    />
  )
}

export {
  Command,
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
  CommandShortcut,
}
