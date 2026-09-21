import { ArrowDownRight, ArrowUpRight } from "lucide-react"
import * as React from "react"

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { cn } from "@/lib/utils"

type Market = "jp" | "us"

type Holding = {
  ticker: string
  name: string
  market: Market
  price: string
  changePct: number
}

const marketLabel: Record<Market, string> = {
  jp: "Nhật (Rakuten)",
  us: "Mỹ (Rakuten)",
}

const holdings: Holding[] = [
  { ticker: "7267.T", name: "Honda Motor", market: "jp", price: "¥1,842", changePct: 1.4 },
  { ticker: "6367.T", name: "Daikin Industries", market: "jp", price: "¥19,120", changePct: -0.8 },
  { ticker: "8306.T", name: "Mitsubishi UFJ FG", market: "jp", price: "¥1,655", changePct: 0.3 },
  { ticker: "AAPL", name: "Apple Inc.", market: "us", price: "$232.10", changePct: 0.9 },
  { ticker: "MSFT", name: "Microsoft Corp.", market: "us", price: "$418.50", changePct: -1.2 },
  { ticker: "NVDA", name: "NVIDIA Corp.", market: "us", price: "$126.80", changePct: 2.6 },
]

export function WatchlistPage() {
  const [market, setMarket] = React.useState<Market | "all">("all")

  const rows = market === "all" ? holdings : holdings.filter((h) => h.market === market)

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between gap-4 space-y-0">
        <div>
          <CardTitle>Watchlist chứng khoán</CardTitle>
          <CardDescription>Dữ liệu mẫu minh họa — không phải giá thực tế, không phải lời khuyên đầu tư</CardDescription>
        </div>
        <Select value={market} onValueChange={(value) => setMarket(value as Market | "all")}>
          <SelectTrigger className="w-40" aria-label="Lọc theo thị trường">
            <SelectValue placeholder="Thị trường" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Tất cả</SelectItem>
            <SelectItem value="jp">Nhật</SelectItem>
            <SelectItem value="us">Mỹ</SelectItem>
          </SelectContent>
        </Select>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Mã</TableHead>
              <TableHead>Tên</TableHead>
              <TableHead>Thị trường</TableHead>
              <TableHead className="text-right">Giá</TableHead>
              <TableHead className="text-right">% Thay đổi</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((h) => (
              <TableRow key={h.ticker}>
                <TableCell className="font-medium">{h.ticker}</TableCell>
                <TableCell className="text-muted-foreground">{h.name}</TableCell>
                <TableCell className="text-muted-foreground">{marketLabel[h.market]}</TableCell>
                <TableCell className="text-right tabular-nums">{h.price}</TableCell>
                <TableCell className="text-right">
                  <Badge
                    variant={h.changePct >= 0 ? "success" : "destructive"}
                    className="ml-auto w-fit"
                  >
                    {h.changePct >= 0 ? (
                      <ArrowUpRight className="size-3" />
                    ) : (
                      <ArrowDownRight className="size-3" />
                    )}
                    <span className={cn("tabular-nums")}>
                      {h.changePct >= 0 ? "+" : ""}
                      {h.changePct.toFixed(1)}%
                    </span>
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
            {rows.length === 0 && (
              <TableRow>
                <TableCell colSpan={5} className="py-8 text-center text-muted-foreground">
                  Không có mã nào trong thị trường này.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}
