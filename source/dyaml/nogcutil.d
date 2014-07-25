//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


// @nogc versions of Phobos functions that are not yet @nogc.
module dyaml.nogcutil;



import std.traits;
import std.range;



/// A NoGC version of std.conv.parse for integer types.
///
/// Differences:
///    overflow parameter - bool set to true if there was integer overflow.
///    Asserts that at least one character was parsed instead of throwing an exception.
///    The caller must validate the inputs before calling parseNoGC.
Target parseNoGC(Target, Source)(ref Source s, uint radix, out bool overflow)
    @safe pure nothrow @nogc
    if (isSomeChar!(ElementType!Source) &&
        isIntegral!Target && !is(Target == enum)) 
in { assert(radix >= 2 && radix <= 36); }
body
{
    immutable uint beyond = (radix < 10 ? '0' : 'a'-10) + radix;

    Target v = 0;
    size_t atStart = true;

    for (; !s.empty; s.popFront())
    {
        uint c = s.front;
        if (c < '0')
            break;
        if (radix < 10)
        {
            if (c >= beyond)
                break;
        }
        else
        {
            if (c > '9')
            {
                c |= 0x20;//poorman's tolower
                if (c < 'a' || c >= beyond) { break; }
                c -= 'a'-10-'0';
            }
        }
        auto blah = cast(Target) (v * radix + c - '0');
        if (blah < v)
        {
            overflow = true;
            return Target.max;
        }
        v = blah;
        atStart = false;
    }
    assert(!atStart, "Nothing to parse in parse()");
    return v;
}
/// Convenience function that returns an $(D AppenderNoGCFixed!A) using with $(D array)
/// for storage.
AppenderNoGCFixed!(E[]) appenderNoGC(A : E[], E)(A array)
{
    return AppenderNoGCFixed!(E[])(array);
}

/// A gutted, NoGC version of std.array.appender.
///
/// Works on a fixed-size buffer.
struct AppenderNoGCFixed(A : T[], T)
{
    import std.array;
    import std.traits;

    private struct Data
    {
        size_t capacity;
        Unqual!T[] arr;
        bool canExtend = false;
    }

    private Data _data;

    @nogc:

    /// Construct an appender that will work with given buffer.
    ///
    /// Data written to the appender will overwrite the buffer from the start.
    this(T[] arr) @trusted pure nothrow
    {
        // initialize to a given array.
        _data.arr = cast(Unqual!T[])arr[0 .. 0]; //trusted

        if (__ctfe)
            return;

        _data.capacity = arr.length;
    }

    /**
     * Returns the capacity of the array (the maximum number of elements the
     * managed array can accommodate before triggering a reallocation).  If any
     * appending will reallocate, $(D capacity) returns $(D 0).
     */
    @property size_t capacity() const @safe pure nothrow
    {
        return _data.capacity;
    }

    /**
     * Returns the managed array.
     */
    @property inout(T)[] data() inout @trusted pure nothrow
    {
        /* @trusted operation:
         * casting Unqual!T[] to inout(T)[]
         */
        return cast(typeof(return))(_data.arr);
    }

    // ensure we can add nelems elements, resizing as necessary
    private void ensureAddable(size_t nelems) @safe pure nothrow
    {
        assert(_data.capacity >= _data.arr.length + nelems,
                "AppenderFixed ran out of space");
    }

    /**
     * Appends one item to the managed array.
     */
    void put(U)(U item) if (is(Unqual!U == T))
    {
        ensureAddable(1);
        immutable len = _data.arr.length;

        auto bigDataFun() @trusted nothrow { return _data.arr.ptr[0 .. len + 1];}
        auto bigData = bigDataFun();

        emplaceRef!T(bigData[len], item);

        //We do this at the end, in case of exceptions
        _data.arr = bigData;
    }

    void put(U)(U[] items) if (is(Unqual!U == T))
    {
        // make sure we have enough space, then add the items
        ensureAddable(items.length);
        immutable len = _data.arr.length;
        immutable newlen = len + items.length;

        auto bigDataFun() @trusted nothrow { return _data.arr.ptr[0 .. newlen];}
        auto bigData = bigDataFun();

        alias UT = Unqual!T;

        bigData[len .. newlen] = items[];

        //We do this at the end, in case of exceptions
        _data.arr = bigData;
    }

    // only allow overwriting data on non-immutable and non-const data
    static if (isMutable!T)
    {
        /**
         * Clears the managed array.  This allows the elements of the array to be reused
         * for appending.
         *
         * Note that clear is disabled for immutable or const element types, due to the
         * possibility that $(D AppenderNoGCFixed) might overwrite immutable data.
         */
        void clear() @safe pure nothrow
        {
            _data.arr = ()@trusted{ return _data.arr.ptr[0 .. 0]; }();
        }
    }
    else
    {
        /// Clear is not available for const/immutable data.
        @disable void clear();
    }
}
