MODULE Modules;  (*Link and load on RISC; NW 20.10.2013 / 9.4.2016*)
  IMPORT SYSTEM, Files;
  CONST 
    versionkey = 1X; MT = 12; DescSize = 80;
    BADARCH = 0;
    RISC5   = 6517618;    (* "rsc" 0x00637372 *)
    ERISC5  = 7878770;    (* "r8x" 0x00783872 *)
    X8664   = 7878761;    (* "i8x" 0x00783869 *)
    CORTEX4 = 7877731;    (* "c4x" 0x00783463 *)
    CORTEX0 = 7876707;    (* "c0x" 0x00783063 *)
    ARM64   = 7878753;    (* "a8x" 0x00783861 *)
    ARM32   = 7877729;    (* "a4x" 0x00783461 *)
    RISCV64 = 7878774;    (* "v8x" 0x00783876 *)
    RISCV32 = 7877750;    (* "v4x" 0x00783476 *)
    WASM    = 7877751;    (* "w4x" 0x00783477 *)

  TYPE Module* = POINTER TO ModDesc;
    Command* = PROCEDURE;
    ModuleName* = ARRAY 32 OF CHAR;

    ModDesc* = RECORD
        name*: ModuleName;
        next*: Module;
        key*, num*, size*, refcnt*: INTEGER;
        data*, code*, imp*, cmd*, ent*, ptr*, unused: INTEGER  (*addresses*)
      END ;

  VAR root*, binroot, M: Module;
    MTOrg*, AllocPtr*, res*: INTEGER;
    importing*, imported*: ModuleName;
    limit: INTEGER;
    binMTOrg, binStart, binAllocPtr: INTEGER;
(*  W: Texts.Writer; *)
    Mlist: ARRAY 16 OF ModuleName;
    heapOrg: INTEGER;

  PROCEDURE Debug(s: ARRAY OF CHAR);
    VAR i, ch: INTEGER;
  BEGIN i:=0;
    REPEAT ch := ORD(s[i]); INC(i);  OUCH(ch)
    UNTIL (ch = 0) OR (i = 32);
  END Debug;

  PROCEDURE Dln;
  BEGIN
    OUCH(10)
  END Dln;

  PROCEDURE ThisFile(name: ARRAY OF CHAR): Files.File;
    VAR i: INTEGER;
      filename: ModuleName;
  BEGIN i := 0;
    WHILE name[i] # 0X DO filename[i] := name[i]; INC(i) END ;
    filename[i] := "."; filename[i+1] := "r"; filename[i+2] := "s"; filename[i+3] := "c"; filename[i+4] := 0X;
    RETURN Files.Old(filename)
  END ThisFile;

  PROCEDURE ThisBinFile(name: ARRAY OF CHAR): Files.File;
    VAR i: INTEGER;
      filename: ModuleName;
  BEGIN i := 0;
    WHILE name[i] # 0X DO filename[i] := name[i]; INC(i) END ;
    filename[i] := "."; filename[i+1] := "b"; filename[i+2] := "i"; filename[i+3] := "n"; filename[i+4] := 0X;
    RETURN Files.New(filename)
  END ThisBinFile;

  PROCEDURE error(n: INTEGER; name: ARRAY OF CHAR);
  BEGIN res := n; importing := name
  END error;

  PROCEDURE Check(s: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN ch := s[0]; res := 1; i := 1;
    IF (ch >= "A") & (ch <= "Z") OR (ch >= "a") & (ch <= "z") THEN
      REPEAT ch := s[i]; INC(i)
      UNTIL ~((ch >= "0") & (ch <= "9") OR (ch >= "A") & (ch <= "Z")
        OR (ch >= "a") & (ch <= "z") OR (ch = ".")) OR (i = 32);
      IF (i < 32) & (ch = 0X) THEN res := 0 END
    END
  END Check;

  PROCEDURE LoadOne(name: ARRAY OF CHAR; VAR newmod, rootmod: Module);
    (*search module in list; if not found, load module.
      res = 0: already present or loaded; res = 2: file not available; res = 3: key conflict;
      res = 4: bad file version; res = 5: corrupted file; res = 7: no space*)
    VAR mod, impmod: Module;
      i, n, key, impkey, mno, nofimps, size: INTEGER;
      p, u, v, w: INTEGER;  (*addresses*)
      ch: CHAR;
      body: Command;
      fixorgP, fixorgD, fixorgT: INTEGER;
      disp, adr, inst, pno, vno, dest, offset: INTEGER;
      name1, impname: ModuleName;
      F: Files.File; R: Files.Rider;
      import: ARRAY 16 OF Module;
  BEGIN mod := rootmod; res := 0; nofimps := 0;
    WHILE (mod # NIL) & (name # mod.name) DO mod := mod.next END ;
    IF mod = NIL THEN (*load*)
      Check(name); Debug("Loading module "); Debug(name); Dln;
      IF res = 0 THEN F := ThisFile(name) ELSE F := NIL; Debug(" Bad module name"); Dln; END ;
      IF F # NIL THEN
        Files.Set(R, F, 0); Files.ReadString(R, name1); Files.ReadInt(R, key); Files.Read(R, ch);
        Files.ReadInt(R, size); importing := name1;
        IF ch = versionkey THEN
          Files.ReadString(R, impname);   (*imports*)
          WHILE (impname[0] # 0X) & (res = 0) DO
            Files.ReadInt(R, impkey);
            LoadOne(impname, impmod, rootmod); import[nofimps] := impmod; importing := name1;
            IF res = 0 THEN
              IF impmod.key = impkey THEN INC(impmod.refcnt); INC(nofimps)
              ELSE error(3, name1); imported := impname; Debug(" Bad import key for "); Debug(name1); Dln;
              END
            END ;
            Files.ReadString(R, impname)
          END
        ELSE error(2, name1); Debug(" Bad version key"); Dln;
        END
      ELSE error(1, name); Debug(" File not found"); Dln;
      END ;
      IF res = 0 THEN (*search for a hole in the list allocate and link*)
        INC(size, DescSize); mod := rootmod;
        WHILE (mod # NIL) & ~((mod.name[0] = 0X) & (mod.size >= size)) DO mod := mod.next END ;
        IF mod = NIL THEN (*no large enough hole was found*)
          IF AllocPtr + size < limit THEN (*allocate*)
            p := AllocPtr; mod := SYSTEM.VAL(Module, p);
            AllocPtr := (p + size + 100H) DIV 20H * 20H; mod.size := AllocPtr - p; mod.num := rootmod.num + 1;
            mod.next := rootmod; rootmod := mod
          ELSE error(7, name1); Debug(" No Space for "); Debug(name); Dln;
          END
        ELSE (*fill hole*) p := SYSTEM.VAL(INTEGER, mod)
        END
      END ; 
      IF res = 0 THEN (*read file*)
        Debug(" for "); Debug(name); Debug(": ");
        Debug("D ");
        INC(p, DescSize); (*allocate descriptor*)
        mod.name := name; mod.key := key; mod.refcnt := 0;
        mod.data := p;  (*data*)
        Debug("M ");
        SYSTEM.PUT(mod.num * 4 + MTOrg, p);  (*module table entry*)
        Debug("T ");
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n, 4) END ;  (*type descriptors*)
        Debug("V ");
        Files.ReadInt(R, n);
        WHILE n > 0 DO SYSTEM.PUT(p, 0); INC(p, 4); DEC(n, 4) END ;  (*variable space*)
        Debug("S ");
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.Read(R, ch); SYSTEM.PUT(p, ch); INC(p); DEC(n) END ;   (*strings*)
        Debug("C ");
        mod.code := p;  (*program*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n) END ;  (*program code*)
        Debug("I ");
        mod.imp := p;  (*copy imports*)
        i := 0;
        WHILE i < nofimps DO
          SYSTEM.PUT(p, import[i]); INC(p, 4); INC(i)
        END ;
        Debug("F ");
        mod.cmd := p;  (*commands*) Files.Read(R, ch);
        WHILE ch # 0X DO
          REPEAT SYSTEM.PUT(p, ch); INC(p); Files.Read(R, ch) UNTIL ch = 0X;
          REPEAT SYSTEM.PUT(p, 0X); INC(p) UNTIL p MOD 4 = 0;
          Files.ReadInt(R, n); SYSTEM.PUT(p, n); INC(p, 4); Files.Read(R, ch)
        END ;
        REPEAT SYSTEM.PUT(p, 0X); INC(p) UNTIL p MOD 4 = 0;
        Debug("E ");
        mod.ent := p;  (*entries*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n) END ;
        Debug("P ");
        mod.ptr := p;  (*pointer references*)
        Files.ReadInt(R, w);
        WHILE w >= 0 DO SYSTEM.PUT(p, mod.data + w); INC(p, 4); Files.ReadInt(R, w) END ;
        SYSTEM.PUT(p, 0); INC(p, 4);
        IF R.eof THEN
          Debug(" Early eof in "); Debug(name); Dln;
          mod := NIL; error(4, name)
        ELSE
          Debug("O ");
          Files.ReadInt(R, fixorgP); Files.ReadInt(R, fixorgD); Files.ReadInt(R, fixorgT);
          Files.ReadInt(R, w); body := SYSTEM.VAL(Command, mod.code + w);
          Files.Read(R, ch);
          IF ch # "O" THEN (*corrupted file*)  
            Debug(" Early eof in "); Debug(name); Dln;
            mod := NIL; error(4, name) 
          ELSE
            Dln
          END
        END
      END ;
      IF res = 0 THEN (*fixup of BL*)
        adr := mod.code + fixorgP*4;
        WHILE adr # mod.code DO
          SYSTEM.GET(adr, inst);
          mno := inst DIV 100000H MOD 10H;
          pno := inst DIV 1000H MOD 100H;
          disp := inst MOD 1000H;
          SYSTEM.GET(mod.imp + (mno-1)*4, impmod);
          SYSTEM.GET(impmod.ent + pno*4, dest); dest := dest + impmod.code;
          offset := (dest - adr - 4) DIV 4;
          SYSTEM.PUT(adr, (offset MOD 1000000H) + 0F7000000H);
          adr := adr - disp*4
        END ;
        (*fixup of LDR/STR/ADD*)
        adr := mod.code + fixorgD*4;
        WHILE adr # mod.code DO
          SYSTEM.GET(adr, inst);
          mno := inst DIV 100000H MOD 10H;
          disp := inst MOD 1000H;
          IF mno = 0 THEN (*global*)
            SYSTEM.PUT(adr, (inst DIV 1000000H * 10H + MT) * 100000H + mod.num * 4)
          ELSE (*import*)
            SYSTEM.GET(mod.imp + (mno-1)*4, impmod); v := impmod.num;
            SYSTEM.PUT(adr, (inst DIV 1000000H * 10H + MT) * 100000H + v*4);
            SYSTEM.GET(adr+4, inst); vno := inst MOD 100H;
            SYSTEM.GET(impmod.ent + vno*4, offset);
            IF ODD(inst DIV 100H) THEN offset := offset + impmod.code - impmod.data END ;
            SYSTEM.PUT(adr+4, inst DIV 10000H * 10000H + offset)
          END ;
          adr := adr - disp*4
        END ;
        (*fixup of type descriptors*)
        adr := mod.data + fixorgT*4;
        WHILE adr # mod.data DO
          SYSTEM.GET(adr, inst);
          mno := inst DIV 1000000H MOD 10H;
          vno := inst DIV 1000H MOD 1000H;
          disp := inst MOD 1000H;
          IF mno = 0 THEN (*global*) inst := mod.data + vno
          ELSE (*import*)
            SYSTEM.GET(mod.imp + (mno-1)*4, impmod);
            SYSTEM.GET(impmod.ent + vno*4, offset);
            inst := impmod.data + offset
          END ;
          SYSTEM.PUT(adr, inst); adr := adr - disp*4
        END ;
        body   (*initialize module*)
      ELSIF res = 3 THEN importing := name;
        WHILE nofimps > 0 DO DEC(nofimps); DEC(import[nofimps].refcnt) END
      END 
    END ;
    newmod :=  mod
  END LoadOne;

  PROCEDURE Load*(name: ARRAY OF CHAR; VAR newmod: Module);
  BEGIN
    LoadOne(name,newmod,root)
  END Load;

  PROCEDURE zero( VAR s: ARRAY OF CHAR);
    VAR i : INTEGER;
  BEGIN i:=0;
    WHILE i < LEN(s) DO s[i]:=0X; INC(i) END
  END zero;


  PROCEDURE LinkOne*(name: ARRAY OF CHAR; VAR newmod, rootmod: Module);
    VAR mod, impmod: Module;
      i, n, key, impkey, mno, nofimps, size: INTEGER;
      p, u, v, w: INTEGER;  (*addresses*)
      ch: CHAR;
      body: Command;
      fixorgP, fixorgD, fixorgT: INTEGER;
      disp, adr, imgadr, inst, pno, vno, dest, offset: INTEGER;
      name1, impname: ModuleName;
      F: Files.File; R: Files.Rider;
      import: ARRAY 16 OF Module;
  BEGIN mod := rootmod; res := 0; nofimps := 0;
    WHILE (mod # NIL) & (name # mod.name) DO mod := mod.next END ;
    IF mod = NIL THEN (*load*)
      F := ThisFile(name);
      IF F # NIL THEN
        Files.Set(R, F, 0);
        zero(name1);
        Files.ReadString(R, name1); Files.ReadInt(R, key); Files.Read(R, ch); Files.ReadInt(R, size);
        zero(importing);
        importing := name1;
        IF ch = versionkey THEN
          zero(impname);
          Files.ReadString(R, impname);   (*imports*)
          WHILE (impname[0] # 0X) & (res = 0) DO
            Files.ReadInt(R, impkey);
            LinkOne(impname, impmod, rootmod); import[nofimps] := impmod; importing := name1;
            IF res = 0 THEN
              IF impmod.key = impkey THEN INC(impmod.refcnt); INC(nofimps)
              ELSE error(3, name1); imported := impname
              END
            END ;
            zero(impname);
            Files.ReadString(R, impname)
          END
        ELSE  error(2, name1)
        END
      ELSE (* error(1, name) *)
      END ;
      IF res = 0 THEN
        INC(size, DescSize);
        IF binAllocPtr + size < limit THEN (*allocate*)
            p:= binAllocPtr;
            i:=p; WHILE i < ((p + size + 100H) DIV 20H * 20H)  DO SYSTEM.PUT( i, 0); INC(i,4) END;
            mod := SYSTEM.VAL(Module, p);
            SYSTEM.PUT( SYSTEM.ADR(binAllocPtr), (p + size + 100H) DIV 20H * 20H);
            mod.size := binAllocPtr - p;
            IF rootmod # NIL THEN  mod.num := rootmod.num + 1
            ELSE mod.num := 1
            END;
            mod.next := rootmod; rootmod := mod
        ELSE error(7, name1)
        END
      END ;
      IF res = 0 THEN (*read file*)
        INC(p, DescSize); (*allocate descriptor*)
        zero(mod.name);
        mod.name := name;
        mod.key := key; mod.refcnt := 0;
        mod.data := p;  (*data*)
        SYSTEM.PUT(mod.num * 4 + binMTOrg, p );  (*module table entry*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w);  SYSTEM.PUT(p, w);  INC(p, 4); DEC(n, 4) END ; (*type descriptors*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO SYSTEM.PUT(p, 0); INC(p, 4); DEC(n, 4) END ;  (*variable space*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.Read(R, ch); SYSTEM.PUT(p, ch); INC(p); DEC(n) END ;   (*strings*)
        mod.code := p;  (*program*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n) END ;  (*program code*)
        mod.imp := p;  (*copy imports*)
        i := 0;
        WHILE i < nofimps DO
          SYSTEM.PUT(p, import[i]); INC(p, 4); INC(i)
        END ;
        mod.cmd := p;  (*commands*)
        Files.Read(R, ch);
        WHILE ch # 0X DO
          REPEAT SYSTEM.PUT(p, ch); INC(p); Files.Read(R, ch) UNTIL ch = 0X;
          REPEAT SYSTEM.PUT(p, 0X); INC(p) UNTIL p MOD 4 = 0;
          Files.ReadInt(R, n); SYSTEM.PUT(p, n); INC(p, 4); Files.Read(R, ch)
        END ;
        REPEAT SYSTEM.PUT(p, 0X); INC(p) UNTIL p MOD 4 = 0;
        mod.ent := p; (*entries*)
        Files.ReadInt(R, n);
        mod.ent := p; (*entries*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n) END ;
        mod.ptr := p; (*pointer references*)
        Files.ReadInt(R, w);
        WHILE w >= 0 DO SYSTEM.PUT(p, mod.data + w - binStart ); INC(p, 4); Files.ReadInt(R, w) END ;
        SYSTEM.PUT(p, 0); INC(p, 4);
        Files.ReadInt(R, fixorgP); Files.ReadInt(R, fixorgD); Files.ReadInt(R, fixorgT);
        Files.ReadInt(R, w); body := SYSTEM.VAL(Command, mod.code + w - binStart );
        Files.Read(R, ch);
        IF ch # "O" THEN (*corrupted file*)  mod := NIL (* ; error(4, name) *) END
      END ;
      IF res = 0 THEN (*fixup of BL*)
        adr := mod.code + fixorgP*4;

        WHILE adr # mod.code DO
          SYSTEM.GET(adr, inst);
          mno := inst DIV 100000H MOD 10H;
          pno := inst DIV 1000H MOD 100H;
          disp := inst MOD 1000H;
          SYSTEM.GET(mod.imp + (mno-1)*4, impmod);
          SYSTEM.GET(impmod.ent + pno*4, dest); dest := dest + impmod.code - binStart;
          offset := (dest - (adr - binStart) - 4) DIV 4;
          SYSTEM.PUT(adr, (offset MOD 1000000H) + 0F7000000H);
          adr := adr - disp*4
        END ;

        (*fixup of LDR/STR/ADD*)
        adr := mod.code + fixorgD*4;
        WHILE adr # mod.code DO
          SYSTEM.GET(adr, inst);
          mno := inst DIV 100000H MOD 10H;
          disp := inst MOD 1000H;
          IF mno = 0 THEN  (*global*)
           SYSTEM.PUT(adr, (inst DIV 1000000H * 10H + MT) * 100000H + mod.num * 4)
         ELSE (*import*)
            SYSTEM.GET(mod.imp + (mno-1)*4, impmod); v := impmod.num;
            SYSTEM.PUT(adr, (inst DIV 1000000H * 10H + MT) * 100000H + v*4);
            SYSTEM.GET(adr+4, inst); vno := inst MOD 100H;
            SYSTEM.GET(impmod.ent + vno*4, offset);
            IF ODD(inst DIV 100H) THEN offset := offset + impmod.code - impmod.data END ;
           SYSTEM.PUT(adr+4, inst DIV 10000H * 10000H + offset  )
          END ;
          adr := adr - disp*4
        END ;

        (*fixup of type descriptors*)

        adr := mod.data + fixorgT*4;
        WHILE adr # mod.data DO
          SYSTEM.GET(adr, inst);
          mno := inst DIV 1000000H MOD 10H;
          vno := inst DIV 1000H MOD 1000H;
          disp := inst MOD 1000H;
          IF mno = 0 THEN                                              (*global*)
             inst := mod.data - binStart + vno
          ELSE                                                                 (*import*)
            SYSTEM.GET(mod.imp + (mno-1)*4, impmod);
            SYSTEM.GET(impmod.ent + vno*4, offset);
            inst := impmod.data + offset - binStart
          END ;
          SYSTEM.PUT(adr, inst); adr := adr - disp*4
    (*      SYSTEM.PUT(adr, 44444444H ); adr := adr - disp*4  *)
        END ;

        SYSTEM.PUT( binStart, body )            (* module initialization vector *)
      ELSIF res = 3 THEN importing := name;
        WHILE nofimps > 0 DO DEC(nofimps); DEC(import[nofimps].refcnt) END
      END
    END;
    newmod :=  mod;
  END LinkOne;



  PROCEDURE Link*(s: ARRAY OF CHAR; VAR rv: INTEGER);
    VAR
      F: Files.File;  R: Files.Rider;
      M, p : Module;
      Lname : ModuleName;
      i,v : INTEGER;
  BEGIN
    Debug("Linking 01 "); Debug(s); Dln;
    binStart := AllocPtr; binMTOrg := binStart + 32; binroot := NIL; res:= 0;
    limit:= heapOrg; DEC(limit, 8000H);
    binAllocPtr :=  binStart+ 256; i:= 0;
    WHILE i < 256+80 DO SYSTEM.PUT(binStart+i, 0 ); INC(i,4) END;
(*
    F:= ThisFile( s );
    IF F # NIL THEN (* LinkOne this module *)
      zero(Lname);
      i:=0; WHILE (s[i] #0X ) & (i < LEN(Lname)) &( i < LEN(s)) DO Lname[i]:=s[i] ; INC(i) END;

      LinkOne( Lname , M, binroot );

      SYSTEM.PUT(binStart + 20,SYSTEM.VAL(INTEGER,binroot) - binStart );
      SYSTEM.PUT(binStart + 252, 12345678H );           (* A fingerprint *)
      p:=SYSTEM.VAL(Module,binroot);
      F:=ThisBinFile(p.name);


      WHILE p # NIL DO  (* fix up module chain of pointers*)
        M:=p;
        p:=p.next;
        IF M.next # NIL THEN M.next := SYSTEM.VAL(Module, SYSTEM.VAL(INTEGER, M.next) - binStart) END;
        M.data := M.data - binStart;
        M.code := M.code - binStart;
        i:=M.imp; WHILE i < M.cmd DO SYSTEM.GET(i,v); SYSTEM.PUT(i,v-binStart);  INC(i,4) END;
        M.imp := M.imp - binStart;
        M.cmd := M.cmd - binStart;
        M.ent := M.ent - binStart;
        M.ptr := M.ptr - binStart ;
        SYSTEM.PUT( binStart + 20H + (4*M.num), M.data )
      END;
      i := binStart;
      Files.Set(R, F, 0);

      SYSTEM.PUT(binStart + 16, binAllocPtr - binStart );       (*size of linked binary file *)
      SYSTEM.PUT(binStart + 24, 40000H );   (* limit / heapOrg *)
      SYSTEM.GET(binStart,v);
      SYSTEM.PUT(binStart, 0E7H * 1000000H + (v DIV 4) -1);      (* Branch to Module start routine *)
      WHILE i < binAllocPtr DO SYSTEM.GET( i, v); Files.WriteInt(R,v); INC(i,4) END;
      Files.Register(F);


    ELSE (* Texts.WriteString(W, " (not found)")  *)
    END

*)
    rv:=res
  END Link;


  PROCEDURE ThisCommand*(mod: Module; name: ARRAY OF CHAR): Command;
    VAR k, adr, w: INTEGER; ch: CHAR;
      s: ARRAY 32 OF CHAR;
  BEGIN res := 5; w := 0;
    IF mod # NIL THEN
      adr := mod.cmd; SYSTEM.GET(adr, ch);
      WHILE (ch # 0X) & (res # 0) DO k := 0; (*read command name*)
        REPEAT s[k] := ch; INC(k); INC(adr); SYSTEM.GET(adr, ch) UNTIL ch = 0X;
        s[k] := 0X;
        REPEAT INC(adr) UNTIL adr MOD 4 = 0;
        SYSTEM.GET(adr, k); INC(adr, 4);
        IF s = name THEN res := 0; w := mod.code + k ELSE SYSTEM.GET(adr, ch) END
      END
    END
    RETURN SYSTEM.VAL(Command, w)
  END ThisCommand;

  PROCEDURE Free*(name: ARRAY OF CHAR);
    VAR mod, imp: Module; p, q: INTEGER;
  BEGIN mod := root; res := 0;
    WHILE (mod # NIL) & (mod.name # name) DO mod := mod.next END ;
    IF mod # NIL THEN
      IF mod.refcnt = 0 THEN
        mod.name[0] := 0X; p := mod.imp; q := mod.cmd;
        WHILE p < q DO SYSTEM.GET(p, imp); DEC(imp.refcnt); INC(p, 4) END ;
      ELSE res := 1
      END
    END
  END Free;

  PROCEDURE Init*;
  BEGIN Files.Init; MTOrg := SYSTEM.REG(MT);
    SYSTEM.GET(16, AllocPtr); SYSTEM.GET(20, root); SYSTEM.GET(24, limit); DEC(limit, 8000H)
  END Init;

BEGIN  OUCH(77);  OUCH(79);  OUCH(68);  OUCH(85);  OUCH(76);  OUCH(69);  OUCH(83);  OUCH(10);
    SYSTEM.GET(24, heapOrg); (*WARNING: Keep in sync with Kernel*)
    LED(1); Init; Load("Oberon", M);
    REPEAT  (*only if load fails*)
      limit := 100000;  (* reuse so as not to change the module signature *)
      REPEAT DEC(limit) UNTIL limit = 0;
      LED(0);  
      limit := 100000;
      REPEAT DEC(limit) UNTIL limit = 0;
      LED(1);  
    UNTIL FALSE
 END Modules.
