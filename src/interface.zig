pub fn hasRelevantReaderMethods(comptime T: type) bool {
    if (!@hasDecl(T, "readByte")) return false;

    {
        const info = @typeInfo(@TypeOf(T.readByte));
        if (info != .Fn) return false;

        const returnType = info.Fn.return_type;
        const returnTypeInfo = @typeInfo(returnType.?);

        if (returnTypeInfo != .ErrorUnion) return false;
        if (returnTypeInfo.ErrorUnion.payload != u8) return false;
    }

    if (!@hasDecl(T, "readNoEof")) return false;

    {
        const info = @typeInfo(@TypeOf(T.readNoEof));
        if (info != .Fn) return false;

        const params = info.Fn.params;
        if (params.len != 2) return false;
        if (params[1].type != []u8) return false;

        const returnType = info.Fn.return_type;
        const returnTypeInfo = @typeInfo(returnType.?);

        if (returnTypeInfo != .ErrorUnion) return false;
        if (returnTypeInfo.ErrorUnion.payload != void) return false;
    }

    return true;
}
