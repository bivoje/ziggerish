
const std = @import("std");

const BFinstr        = @import("types.zig").BFinstr;
const CompileOptions = @import("types.zig").CompileOptions;

const system = @import("util.zig").system;

pub fn compile (
    tokens: std.ArrayList(BFinstr),
    options: CompileOptions,
) !void {

    const ll = options.method.ll;

    var file = try std.fs.cwd().createFile(ll.temp_path_ll, .{ .read = true, });
    defer file.close();
    var w = file.writer();


    try w.print(
        \\source_filename = "{s}"
        \\target triple = "x86_64-pc-linux-gnu"
        \\
    , .{options.src_path});

    try w.writeAll(
        \\@buf = internal global [1000 x i8] zeroinitializer, align 16
        \\define internal fastcc void @intgetchar(i8* nocapture %0) unnamed_addr #1 {
        \\  %2 = call i64 @read(i32 0, i8* %0, i64 1) #5
        \\  %3 = icmp eq i64 %2, 1
        \\  br i1 %3, label %readret, label %readeof
        \\readeof:
        \\  store i8 -1, i8* %0, align 1, !tbaa !2
        \\  br label %readret
        \\readret:
        \\  ret void
        \\}
        \\define internal fastcc void @intputchar(i8* nocapture readonly %0) unnamed_addr #1 {
        \\  %2 = call i64 @write(i32 1, i8* %0, i64 1) #5
        \\  ret void
        \\}
        \\define internal fastcc void @dump(i8* nocapture %ptr) unnamed_addr #1 {
        \\entry:
        \\  %c = alloca i8, align 1
        \\  %p_base = getelementptr inbounds [1000 x i8], [1000 x i8]* @buf, i64 0, i64 0
        \\  %p_end = getelementptr inbounds i8, i8* %ptr, i64 5
        \\
        \\  %do_nothing = icmp eq i8* %p_base, %p_end
        \\  br i1 %do_nothing, label %done, label %loop
        \\
        \\loop:
        \\  %p0 = phi i8* [ %p_base, %entry ], [ %p1, %loop ]
        \\
        \\  %ca0 = load i8, i8* %p0, align 1
        \\  %ca1 = lshr i8 %ca0, 4
        \\  %ca2 = or i8 %ca1, 48
        \\  %ba = icmp ult i8 %ca2, 58
        \\  %da = select i1 %ba, i8 0, i8 7
        \\  %ca3 = add nuw nsw i8 %da, %ca2
        \\  store i8 %ca3, i8* %c, align 1
        \\  call void @intputchar(i8* nonnull %c)
        \\
        \\  %cb0 = load i8, i8* %p0, align 1
        \\  %cb1 = and i8 %cb0, 15
        \\  %cb2 = or i8 %cb1, 48
        \\  %bb = icmp ult i8 %cb2, 58
        \\  %db = select i1 %bb, i8 0, i8 7
        \\  %cb3  = add nuw nsw i8 %cb2, %db
        \\  store i8 %cb3, i8* %c, align 1
        \\  call void @intputchar(i8* nonnull %c)
        \\
        \\  store i8 32, i8* %c, align 1
        \\  call void @intputchar(i8* nonnull %c)
        \\
        \\  %p1 = getelementptr inbounds i8, i8* %p0, i64 1
        \\  %finished = icmp eq i8* %p1, %p_end
        \\  br i1 %finished, label %done, label %loop
        \\
        \\done:
        \\  store i8 10, i8* %c, align 1
        \\  call void @intputchar(i8* nonnull %c)
        \\  ret void
        \\}
        \\define dso_local void @main() local_unnamed_addr #0 {
        \\loop0b0:
        \\  %l0p0 = getelementptr inbounds [1000 x i8], [1000 x i8]* @buf, i64 0, i64 0
        \\
    );

    const tl = try translate(w, 0, tokens, 0, 1, 0, 0, options);
    // TODO check more sophisticately
    try std.testing.expectEqual(tl.@"0", tokens.items.len);

    try w.writeAll(
        \\  br label %mainret
        \\mainret:
        \\  call void @exit(i32 0) #4
        \\  unreachable
        \\}
        \\declare dso_local void @exit(i32) local_unnamed_addr #2
        \\declare dso_local i64 @write(i32, i8* nocapture readonly, i64) local_unnamed_addr #3
        \\declare dso_local i64 @read(i32, i8* nocapture, i64) local_unnamed_addr #3
        \\
        \\attributes #0 = { noreturn nounwind uwtable "disable-tail-calls"="false" "frame-pointer"="none" "no-jump-tables"="false"  "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87"}
        \\attributes #1 = { nofree nounwind uwtable "disable-tail-calls"="false" "frame-pointer"="none" "no-jump-tables"="false" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" }
        \\attributes #2 = { noreturn nounwind "disable-tail-calls"="false" "frame-pointer"="none" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" }
        \\attributes #3 = { nofree "correctly-rounded-divide-sqrt-fp-math"="false" "disable-tail-calls"="false" "frame-pointer"="none" "less-precise-fpmad"="false" "no-infs-fp-math"="false" "no-nans-fp-math"="false" "no-signed-zeros-fp-math"="false" "no-trapping-math"="false" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "unsafe-fp-math"="false" "use-soft-float"="false" }
        \\attributes #4 = { noreturn nounwind }
        \\attributes #5 = { nounwind }
        \\
        \\!llvm.module.flags = !{!0}
        \\!llvm.ident = !{!1}
        \\
        \\!0 = !{i32 1, !"wchar_size", i32 4}
        \\!1 = !{!"clang version 10.0.0-4ubuntu1 "}
        \\!2 = !{!3, !3, i64 0}
        \\!3 = !{!"omnipotent char", !4, i64 0}
        \\!4 = !{!"Simple C/C++ TBAA"}
        \\
    );

    const ret_clang = try system(
        "clang",
        &[_:null]?[*:0]const u8{
            "clang",
            "-o", options.dst_path,
            ll.temp_path_ll,
            null,
        }, &[_:null]?[*:0]const u8{
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            null
        }
    );

    if (ret_clang.status != 0) return error.ClangError;
}

fn translate (
    w: std.fs.File.Writer,
    _ti: usize,
    tokens: std.ArrayList(BFinstr),
    ln: usize, // current level num
    _ln: usize, // level num of the block above
    _lx: usize, // level sub-num of the block above
    _px: usize, // ptr num of last loaded
    options: CompileOptions,
) std.fs.File.Writer.Error ! struct {@"0":usize,@"1":usize} { // returns the number of tokens read

    var ln_ = ln+1;       // next ln to allocate
    //dprint("translate(ti={}, ln={}, ln_={}, _lx={})\n", .{_ti, ln, ln_, _lx});

    var ti = _ti;
    _ = _px;

    // varnum of last updated value
    var vx: usize = 1;
    var px: usize = 0;
    var lx: usize = 0;

    blk: while (ti < tokens.items.len) : (ti += 1) {
        const token = tokens.items[ti];
        //dprint("tokens[{}]: {}\n", .{ti, token});
        switch (token) {
            .Dump  => { // #
                try w.print("  call fastcc void @dump(i8* nonnull %l{}p{})", .{ln,px});
                try w.print("\t\t;dump", .{});
            },
            .Left  => { // <
                try w.print("  %l{}p{} = getelementptr inbounds i8, i8* %l{}p{}, i64 -1", .{ln,px+1, ln,px});
                try w.print("\t\t;<", .{});
                px += 1;
            },
            .Right => { // >
                try w.print("  %l{}p{} = getelementptr inbounds i8, i8* %l{}p{}, i64 1", .{ln,px+1, ln,px});
                try w.print("\t\t;>", .{});
                px += 1;
            },
            .Inc   => { // +
                try w.print(
                    \\  %l{}v{} = load i8, i8* %l{}p{}, align 16
                    \\  %l{}v{} = add i8 %l{}v{}, 1
                    \\  store i8 %l{}v{}, i8* %l{}p{}, align 16
                ,.{ ln,vx+1, ln,px,
                    ln,vx+2, ln,vx+1,
                    ln,vx+2, ln,px, });
                try w.print("\t\t\t;+", .{});
                vx += 2;
            },
            .Dec   => { // -
                try w.print(
                    \\  %l{}v{} = load i8, i8* %l{}p{}, align 16
                    \\  %l{}v{} = sub i8 %l{}v{}, 1
                    \\  store i8 %l{}v{}, i8* %l{}p{}, align 16
                ,.{ ln,vx+1, ln,px,
                    ln,vx+2, ln,vx+1,
                    ln,vx+2, ln,px, });
                try w.print("\t\t\t;-", .{});
                vx += 2;
            },
            .Get   => { // ,
                try w.print("  call fastcc void @intgetchar(i8* nonnull %l{}p{})", .{ln,px});
                try w.print("\t\t;get", .{});
            },
            .Put   => { // .
                try w.print("  call fastcc void @intputchar(i8* nonnull %l{}p{})", .{ln,px});
                try w.print("\t\t;put", .{});
            },
            .From  => { // [
                try w.print("  br label %loop{}a\n", .{ln_});
                try w.print(
                    \\loop{}a:
                    \\  %l{}p{} = phi i8* [ %l{}p{}, %loop{}b{} ], [ %l{}p_, %loop{}c ]
                    //\\  call fastcc void @intputchar(i8* nonnull %l{}p{})
                    \\  %l{}v{} = load i8, i8* %l{}p{}, align 16
                    \\  %l{}v{} = icmp eq i8 %l{}v{}, 0
                    \\  br i1 %l{}v{}, label %loop{}c, label %loop{}b{}
                    \\loop{}b{}:
                    \\
                ,.{ ln_,
                    ln_,0, ln,px, ln,lx, ln_, ln_,
                    //ln_,0,
                    ln_,0, ln_,0,
                    ln_,1, ln_,0,
                    ln_,1, ln_, ln_,0,
                    ln_,0
                });
                try w.print("\t\t\t\t\t;[\n", .{});
                const tl = try translate(w, ti+1, tokens, ln_, ln, lx, px, options);
                try w.print(
                    \\loop{}b{}:
                    \\  %l{}p{} = getelementptr inbounds i8, i8* %l{}p_, i64 0
                ,.{ ln,lx+1,
                    ln,px+1, ln_,
                });
                ti += tl.@"0";
                ln_ = tl.@"1";
                lx += 1;
                px += 1;
            },
            .To => { // ]
                try w.print(
                    \\  br label %loop{}c
                    \\loop{}c:
                    \\  %l{}p_ = phi i8* [ %l{}p{}, %loop{}a ], [ %l{}p{}, %loop{}b{} ]
                    //\\  call fastcc void @intputchar(i8* nonnull %l{}p_)
                    \\  %l{}v{} = load i8, i8* %l{}p_, align 16
                    \\  %l{}v{} = icmp eq i8 %l{}v{}, 0
                    \\  br i1 %l{}v{}, label %loop{}b{}, label %loop{}a
                    \\
                ,.{ ln,
                    ln,
                    ln, ln,0, ln, ln,px, ln,lx,
                    //ln,
                    ln,vx+1, ln,
                    ln,vx+2, ln,vx+1,
                    ln,vx+2, _ln,_lx+1, ln
                });
                try w.print("\t\t\t\t\t;]\n", .{});
                vx += 2; // useless but justin-case
                ti += 1; // needed as 'continue expr' not executed
                break :blk;
            },
        } // switch
        try w.print("\n", .{});
    } // while

    //dprint("return(ln={}, ln_={}) {}\n", .{ln, ln_, ti-_ti});
    const vv = .{ .@"0"=ti-_ti, .@"1"=ln_ };
    return vv;
}

