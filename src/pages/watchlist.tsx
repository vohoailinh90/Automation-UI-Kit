import { ArrowDownRight, ArrowUpRight } from "lucide-react"

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

type Holding = {
  ticker: string
  name: string
  market: "Nhật (Rakuten)" | "Mỹ (Rakuten)"
  price: string
  changePct: number
}

const holdings: Holding[] = [
  { ticker: "7267.T", name: "Honda Motor", market: "Nhật (Rakuten)", price: "¥1,842", changePct: 1.4 },
  { ticker: "6367.T", name: "Daikin Industries", market: "Nhật (Rakuten)", price: "¥19,120", changePct: -0.8 },
  { ticker: "8306.T", name: "Mitsubishi UFJ FG", market: "Nhật (Rakuten)", price: "¥1,655", changePct: 0.3 },
  { ticker: "AAPL", name: "Apple Inc.", market: "Mỹ (Rakuten)", price: "$232.10", changePct: 0.9 },
  { ticker: "MSFT", name: "Microsoft Corp.", market: "Mỹ (Rakuten)", price: "$418.50", changePct: -1.2 },
  { ticker: "NVDA", name: "NVIDIA Corp.", market: "Mỹ (Rakuten)", price: "$126.80", changePct: 2.6 },
]

export function WatchlistPage() {
  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between gap-4 space-y-0">
        <div>
          <CardTitle>Watchlist chứng khoán</CardTitle>
          <CardDescription>Dữ liệu mẫu minh họa — không phải giá thực tế, không phải lời khuyên đầu tư</CardDescription>
        </div>
        <Select defaultValue="all">
          <SelectTrigger className="w-40">
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
            {holdings.map((h) => (
              <TableRow key={h.ticker}>
                <TableCell className="font-medium">{h.ticker}</TableCell>
                <TableCell className="text-muted-foreground">{h.name}</TableCell>
                <TableCell className="text-muted-foreground">{h.market}</TableCell>
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
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}
