import { useTable } from "@tanstack/react-table"
import {
  createSortedRowModel,
  rowSortingFeature,
  sortFn_alphanumeric,
  sortFn_basic,
  sortFn_text,
  tableFeatures,
  type ColumnDef,
  type RowData,
  type SortingState,
} from "@tanstack/table-core"
import { ChevronDown, ChevronUp, ChevronsUpDown } from "lucide-react"

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { cn } from "@/lib/utils"

/**
 * TanStack Table v9 gom cả feature lẫn row model vào một object khai báo tĩnh.
 * Khai ở ngoài component là cố ý: đây là cấu hình bất biến, dựng lại mỗi lần
 * render thì mất hết memo hoá bên trong bảng.
 *
 * Chỉ bật đúng thứ đang dùng (sắp xếp). Đó là điểm chính của v9 — feature nào
 * không khai thì không vào bundle.
 */
const features = tableFeatures({
  rowSortingFeature,
  sortedRowModel: createSortedRowModel(),
  sortFns: {
    alphanumeric: sortFn_alphanumeric,
    basic: sortFn_basic,
    text: sortFn_text,
  },
  // v9 khai kiểu meta ngay tại đây thay vì declaration merging toàn cục như v8,
  // nên hai bảng khác nhau có thể có meta khác nhau mà không đụng nhau.
  columnMeta: {} as { align?: "left" | "right" },
})

export type DataTableColumn<TData extends RowData> = ColumnDef<typeof features, TData, unknown>

const sortIcon = { asc: ChevronUp, desc: ChevronDown } as const

/** Giá trị `aria-sort` đúng chuẩn cho `<th>`; screen reader đọc được chiều sắp xếp. */
const ariaSort = { asc: "ascending", desc: "descending" } as const

export function DataTable<TData extends RowData>({
  columns,
  data,
  initialSorting,
  emptyMessage = "Không có dữ liệu.",
  onRowClick,
  isRowActive,
  caption,
}: {
  columns: DataTableColumn<TData>[]
  data: TData[]
  initialSorting?: SortingState
  emptyMessage?: string
  onRowClick?: (row: TData) => void
  isRowActive?: (row: TData) => boolean
  caption?: string
}) {
  const table = useTable({
    features,
    data,
    columns,
    initialState: initialSorting ? { sorting: initialSorting } : undefined,
  })

  const rows = table.getRowModel().rows

  return (
    <Table>
      {caption && <caption className="sr-only">{caption}</caption>}
      <TableHeader>
        {table.getHeaderGroups().map((group) => (
          <TableRow key={group.id}>
            {group.headers.map((header) => {
              const sorted = header.column.getIsSorted()
              const canSort = header.column.getCanSort()
              const Icon = sorted ? sortIcon[sorted] : ChevronsUpDown
              const align = header.column.columnDef.meta?.align === "right"

              return (
                <TableHead
                  key={header.id}
                  aria-sort={sorted ? ariaSort[sorted] : canSort ? "none" : undefined}
                  className={align ? "text-right" : undefined}
                >
                  {header.isPlaceholder ? null : canSort ? (
                    // Nút thật chứ không phải <th onClick>: cần bấm được bằng
                    // bàn phím và cần có tên để screen reader đọc.
                    <button
                      type="button"
                      onClick={header.column.getToggleSortingHandler()}
                      className={cn(
                        "-mx-2 inline-flex items-center gap-1 rounded px-2 py-1 font-medium",
                        "hover:text-foreground focus-visible:ring-ring/50 focus-visible:outline-none focus-visible:ring-2",
                        align && "ml-auto",
                      )}
                    >
                      <table.FlexRender header={header} />
                      <Icon
                        className={cn("size-3.5 shrink-0", !sorted && "text-muted-foreground/60")}
                        aria-hidden
                      />
                    </button>
                  ) : (
                    <table.FlexRender header={header} />
                  )}
                </TableHead>
              )
            })}
          </TableRow>
        ))}
      </TableHeader>
      <TableBody>
        {rows.map((row) => {
          const active = isRowActive?.(row.original) ?? false
          return (
            <TableRow
              key={row.id}
              onClick={onRowClick ? () => onRowClick(row.original) : undefined}
              aria-selected={onRowClick ? active : undefined}
              className={cn(onRowClick && "cursor-pointer", active && "bg-muted/60")}
            >
              {row.getAllCells().map((cell) => (
                <TableCell
                  key={cell.id}
                  className={cell.column.columnDef.meta?.align === "right" ? "text-right" : undefined}
                >
                  <table.FlexRender cell={cell} />
                </TableCell>
              ))}
            </TableRow>
          )
        })}
        {rows.length === 0 && (
          <TableRow>
            <TableCell colSpan={columns.length} className="py-8 text-center text-muted-foreground">
              {emptyMessage}
            </TableCell>
          </TableRow>
        )}
      </TableBody>
    </Table>
  )
}
