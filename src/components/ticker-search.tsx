import { SearchIcon } from "lucide-react"
import * as React from "react"

import { Button } from "@/components/ui/button"
import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandShortcut,
} from "@/components/ui/command"
import { formatPrice, marketLabel, type Instrument, type Market } from "@/lib/market"

/** macOS dùng ⌘, còn lại dùng Ctrl — hiện sai phím tắt thì thà đừng hiện. */
function isMacLike() {
  if (typeof navigator === "undefined") return false
  return /Mac|iPhone|iPad/.test(navigator.userAgent)
}

const markets: Market[] = ["jp", "us"]

/**
 * Tìm mã chứng khoán kiểu ⌘K — thao tác chuẩn của mọi app giao dịch.
 *
 * Lọc để cmdk tự làm (`value` + `keywords`) thay vì tự viết: nó đã lo sẵn phần
 * chấm điểm mờ và điều hướng bằng phím mũi tên.
 */
export function TickerSearch({
  instruments,
  onSelect,
}: {
  instruments: Instrument[]
  onSelect: (ticker: string) => void
}) {
  const [open, setOpen] = React.useState(false)
  const [mac] = React.useState(isMacLike)

  React.useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key.toLowerCase() !== "k") return
      if (!event.metaKey && !event.ctrlKey) return
      // Chặn mặc định của trình duyệt (Ctrl+K là thanh địa chỉ trên vài trình duyệt).
      event.preventDefault()
      setOpen((prev) => !prev)
    }
    document.addEventListener("keydown", onKeyDown)
    return () => document.removeEventListener("keydown", onKeyDown)
  }, [])

  function choose(ticker: string) {
    onSelect(ticker)
    setOpen(false)
  }

  return (
    <CommandDialog
      open={open}
      onOpenChange={setOpen}
      title="Tìm mã chứng khoán"
      description="Gõ mã hoặc tên công ty để mở chart của mã đó."
      trigger={
        <Button
          variant="outline"
          className="w-full justify-start gap-2 text-muted-foreground sm:w-56"
        >
          <SearchIcon className="size-4 shrink-0" aria-hidden />
          Tìm mã...
          <CommandShortcut className="ml-auto">{mac ? "⌘K" : "Ctrl K"}</CommandShortcut>
        </Button>
      }
    >
      <CommandInput placeholder="Gõ mã hoặc tên công ty..." />
      <CommandList>
        <CommandEmpty>Không tìm thấy mã nào.</CommandEmpty>
        {markets.map((market) => {
          const rows = instruments.filter((i) => i.market === market)
          if (rows.length === 0) return null
          return (
            <CommandGroup key={market} heading={marketLabel[market]}>
              {rows.map((item) => (
                <CommandItem
                  key={item.ticker}
                  value={item.ticker}
                  // Tìm được cả bằng tên công ty chứ không chỉ mã — người dùng
                  // thường nhớ "Honda" trước khi nhớ "7267.T".
                  keywords={[item.name]}
                  onSelect={() => choose(item.ticker)}
                >
                  <span className="font-medium">{item.ticker}</span>
                  <span className="truncate text-muted-foreground">{item.name}</span>
                  <span className="ml-auto shrink-0 tabular-nums text-muted-foreground">
                    {formatPrice(item.price, item.currency)}
                  </span>
                </CommandItem>
              ))}
            </CommandGroup>
          )
        })}
      </CommandList>
    </CommandDialog>
  )
}
