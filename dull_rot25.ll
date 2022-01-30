; ModuleID = 'dull_rot25.c'
source_filename = "dull_rot25.c"
; gen by `clang -S -emit-llvm dull_rot25.c`
; then manually edited, use followings to compile
; # llc dull_rot25.ll -o temp.s
; # ld dull_rot25.o -o dull_rot25
; # or
; # above does not work, guess its because llc is static compiler, and does not allow dynamic linking?
; # gcc-generated assemblies as @plt prefixes which enables dynamic linking https://stackoverflow.com/a/5469334
; clang dull_rot25.ll -o dull_rot25
; or statically
; llc dull_rot25.ll -o temp.s
; as temp.s -o temp.o
; ld temp.o -o temp --static -e main -L/usr/lib/gcc/x86_64-linux-gnu/9 -'(' -lgcc -lgcc_eh -lc -')' # --build-id -m elf_x86_64 -z relro
; # note that -lgcc -lgcc_eh is required to statically link which is located in /usr/lib/gcc/x86_64-linux-gnu/9 and
; # -( -)  is required to resolve circular reference within libs https://stackoverflow.com/a/5651895
; # also note that arg order matters, you can't put -l in front of -L

; what for?
;target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

@buf = internal global [1000 x i8] zeroinitializer, align 16

; Function Attrs: nofree nounwind uwtable
define internal fastcc void @intgetchar(i8* nocapture %0) unnamed_addr #1 {
  %2 = call i64 @read(i32 0, i8* %0, i64 1) #5
  %3 = icmp eq i64 %2, 1
  br i1 %3, label %readret, label %readeof

readeof:                                          ; preds = %1
  store i8 -1, i8* %0, align 1, !tbaa !2
  br label %readret

readret:                                          ; preds = %1, %readeof
  ret void
}

; Function Attrs: nofree nounwind uwtable
define internal fastcc void @intputchar(i8* nocapture readonly %0) unnamed_addr #1 {
  %2 = call i64 @write(i32 1, i8* %0, i64 1) #5
  ret void
}

; Function Attrs: noreturn nounwind uwtable
; dso_loca: static symbols,
define dso_local void @main() local_unnamed_addr #0 {
entry:
  %lp0a = getelementptr inbounds [1000 x i8], [1000 x i8]* @buf, i64 0, i64 0
  							; ptr = buf;
  %lv0a = load i8, i8* %lp0a, align 16
  %lv0b = add i8 %lv0a, 1
  store i8 %lv0b, i8* %lp0a, align 16			; ++*ptr;

  br label %loop1a

loop1a:						;; preds = %entry, %loop1c
  %lp1a = phi i8* [ %lp0a, %entry ], [ %lp1b, %loop1c ]
  %lv1a = load i8, i8* %lp1a, align 16
  %lv1b = icmp eq i8 %lv1a, 0
  br i1 %lv1b, label %loop1c, label %loop1b 		; [ // jump to ] if 0

loop1b:						;; preds = %loop1a
  ; we need phi to assign to %4 conditionally, as we cannot assign to %4 in different blocks
  ; getelementptr ... is needed to pointer casting from [1000 x i8]* to i8*
  ; loads the variable that stores last updated ptr in this block if looping

  %lp1c = getelementptr inbounds i8, i8* %lp1a, i64 1	; ++ptr

  call fastcc void @intgetchar(i8* nonnull %lp1c) 	; intgetchar(ptr);

  %lv1e = load i8, i8* %lp1c, align 1
  %lv1f = add i8 %lv1e, -1
  store i8 %lv1f, i8* %lp1c, align 1			; --*ptr;

  call fastcc void @intputchar(i8* nonnull %lp1c)	; intputchar(ptr);

  %lv1g = load i8, i8* %lp1c, align 1
  %lv1h = add i8 %lv1g, 2
  store i8 %lv1h, i8* %lp1c, align 1			; ++*ptr; ++*ptr;

  br label %loop1c

loop1c:						;; preds = %loop1a, %loop1b
  %lp1b = phi i8* [ %lp1a, %loop1a ], [ %lp1c, %loop1b ]
  %lv1c = load i8, i8* %lp1b, align 16
  %lv1d = icmp eq i8 %lv1c, 0
  br i1 %lv1d, label %mainret, label %loop1a		; ] // jump to [ if not 0

mainret:					;; preds = %loop1b
  call void @exit(i32 0) #4
  unreachable
}

; Function Attrs: noreturn nounwind
declare dso_local void @exit(i32) local_unnamed_addr #2

; Function Attrs: nofree
declare dso_local i64 @write(i32, i8* nocapture readonly, i64) local_unnamed_addr #3

; Function Attrs: nofree
declare dso_local i64 @read(i32, i8* nocapture, i64) local_unnamed_addr #3

attributes #0 = { noreturn nounwind uwtable "disable-tail-calls"="false" "frame-pointer"="none" "no-jump-tables"="false"  "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87"}
attributes #1 = { nofree nounwind uwtable "disable-tail-calls"="false" "frame-pointer"="none" "no-jump-tables"="false" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" }
attributes #2 = { noreturn nounwind "disable-tail-calls"="false" "frame-pointer"="none" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" }
attributes #3 = { nofree "correctly-rounded-divide-sqrt-fp-math"="false" "disable-tail-calls"="false" "frame-pointer"="none" "less-precise-fpmad"="false" "no-infs-fp-math"="false" "no-nans-fp-math"="false" "no-signed-zeros-fp-math"="false" "no-trapping-math"="false" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "unsafe-fp-math"="false" "use-soft-float"="false" }
attributes #4 = { noreturn nounwind }
attributes #5 = { nounwind }

!llvm.module.flags = !{!0}
!llvm.ident = !{!1}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{!"clang version 10.0.0-4ubuntu1 "}
!2 = !{!3, !3, i64 0}
!3 = !{!"omnipotent char", !4, i64 0}
!4 = !{!"Simple C/C++ TBAA"}
