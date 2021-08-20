(* begin-package-description
### _Package Overview:_
The Modules package manages the loading and linking and unloading of program code and is the first code run when the boot loader passes control to the OS.


### _Package Use:_

USAGE:
```
Modules.Load("something",M)
```

### _Modules in this package:_
end-package-description *)

(* begin-module-short-description
implements module loading and linking in Oberon.
end-module-short-description *)

(* begin-module-use-description
Module Modules is the heart of how separately compiled Oberon programs are loaded and linked.

end-module-use-description *)
(* begin-module-develop-description

(Link and load on RISC; NW 20.10.2013 / 8.1.2019)

After the BootLoader loads the Inner Core (`Kernel`, `FileDir`, `Files`, `Modules`) into memory, the 
BEGIN section at the end of this module is the next code to execute. Modules, Files, Filedir, and Kernel
cooperate in initializing the state of the Oberon system.

Once the system is initialized, `Modules` dynamically loads the `Oberon` module which recursively requires `Input`, `Display`, `Viewers`, `Fonts`, and `Texts` to also be loaded.

The `Oberon` module in turn, at the end of its initialization, dynamically loads the `System` module which further requires `MenuViewers` and `TextFrames`.

At this point the Oberon system is responsive to user commands.

end-module-develop-description *)
MODULE Modules;  (*Link and load on RISC; NW 20.10.2013 / 8.1.2019*)
  IMPORT SYSTEM, Files;

  CONST 
    versionkey = 1X; 
    MT         = 12; 
    DescSize   = 80;

  TYPE 
    Module*     = POINTER TO ModDesc;
    Command*    = PROCEDURE;
    ModuleName* = ARRAY 32 OF CHAR;

    ModDesc* = RECORD (* 80 bytes *)
        name*: ModuleName;
        next*: Module;
        key*, num*, size*, refcnt*: INTEGER;
        data*, code*, imp*, cmd*, ent*, ptr*, unused: INTEGER  (*addresses*)
      END ;

  VAR 
    root*, M: Module;
    MTOrg*, AllocPtr*, res*: INTEGER;
    importing*, imported*: ModuleName;
    limit: INTEGER;

  (* begin-procedure-description
---
**ThisFile** appends `.rsc` to the module name, opens it, and returns the file.
  end-procedure-description *)
  PROCEDURE ThisFile(name: ARRAY OF CHAR): Files.File;
    VAR i: INTEGER;
      filename: ModuleName;
  BEGIN i := 0;
    WHILE name[i] # 0X DO filename[i] := name[i]; INC(i) END ;
    filename[i] := "."; filename[i+1] := "r"; filename[i+2] := "s"; filename[i+3] := "c"; filename[i+4] := 0X;
    RETURN Files.Old(filename)
  END ThisFile;

  (* begin-procedure-description 
---
**error** places the error number and error name in global varaibles `res` and `importing` for later reference.
  end-procedure-description *)
  PROCEDURE error(n: INTEGER; name: ARRAY OF CHAR);
  BEGIN res := n; importing := name;
  END error;

  (* begin-procedure-description 
---
**Check** conditionally sets global variable `res` to 0 (valid) or 1 (invalid) when checking to see if the string is a valid name. 
  end-procedure-description *)
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

  PROCEDURE OUCH(i:INTEGER);
  BEGIN
  END OUCH;

  (* begin-procedure-description
---
**Debug** Outputs a string to debug special hardware port.
  end-procedure-description *)
  PROCEDURE Debug(s: ARRAY OF CHAR);
    VAR i, ch: INTEGER;
  BEGIN i:=0;
    REPEAT ch := ORD(s[i]); INC(i);  OUCH(ch) 
    UNTIL (ch = 0) OR (i = 32);
  END Debug;


  (* begin-procedure-description 
---
**Load** recursively loads from disk into the module area of memory the imports of a module and then the module itself. 
  end-procedure-description *)
  PROCEDURE Load*(name: ARRAY OF CHAR; VAR newmod: Module);
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
  BEGIN mod := root; error(0, name); nofimps := 0;
    WHILE (mod # NIL) & (name # mod.name) DO mod := mod.next END ;
    IF mod = NIL THEN (*load*)
      Check(name);
      OUCH(10);  Debug("Loading "); Debug(name);
      IF res = 0 THEN F := ThisFile(name) ELSE F := NIL; Debug(" Bad module name: "); Debug(name); OUCH(10); END ;
      IF F # NIL THEN
        Files.Set(R, F, 0); Files.ReadString(R, name1); Files.ReadInt(R, key); Files.Read(R, ch);
        Files.ReadInt(R, size); importing := name1;
        IF ch = versionkey THEN
          Files.ReadString(R, impname);   (*imports*)
          WHILE (impname[0] # 0X) & (res = 0) DO
            Files.ReadInt(R, impkey); 
            Load(impname, impmod); import[nofimps] := impmod; importing := name1;
            IF res = 0 THEN
              IF impmod.key = impkey THEN INC(impmod.refcnt); INC(nofimps)
              ELSE error(3, name1); imported := impname; Debug(" Bad import key for "); Debug(name1); OUCH(10)
              END
            END ;
            Files.ReadString(R, impname)
          END
        ELSE error(2, name1); Debug(" Bad version key"); OUCH(10)
        END
      ELSE error(1, name); Debug(" File not found"); OUCH(10)
      END ;
      IF res = 0 THEN (*search for a hole in the list allocate and link*)
        INC(size, DescSize); mod := root;
        WHILE (mod # NIL) & ~((mod.name[0] = 0X) & (mod.size >= size)) DO mod := mod.next END ;
        IF mod = NIL THEN (*no large enough hole was found*)
          IF AllocPtr + size < limit THEN (*allocate*)
            p := AllocPtr; mod := SYSTEM.VAL(Module, p);
            AllocPtr := (p + size + 100H) DIV 20H * 20H; mod.size := AllocPtr - p; mod.num := root.num + 1;
            mod.next := root; root := mod
          ELSE error(7, name1); Debug(" No Space for "); Debug(name); OUCH(10)
          END
        ELSE (*fill hole*) p := SYSTEM.VAL(INTEGER, mod)
        END
      END ; 
      IF res = 0 THEN (*read file*)
        OUCH(10); Debug(" for "); Debug(name); Debug(": ");
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
          Files.ReadInt(R, n); SYSTEM.PUT(p, n); INC(p, 4); (* address *)
(*        Files.ReadInt(R, n); SYSTEM.PUT(p, n); INC(p, 4); Files.Read(R, ch) (* frame size *)   *)
        END ;
        REPEAT SYSTEM.PUT(p, 0X); INC(p) UNTIL p MOD 4 = 0;
        Debug("E ");
        mod.ent := p;  (*entries*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n) END ;
        Debug("P ");
        mod.ptr := p;  (*pointer references*)
        Files.ReadInt(R, w);
        WHILE ~(R.eof) & (w >= 0) DO SYSTEM.PUT(p, mod.data + w); INC(p, 4); Files.ReadInt(R, w) END ;
        SYSTEM.PUT(p, 0); INC(p, 4);
        IF R.eof THEN Debug(" Early eof in "); Debug(name); OUCH(10); END;
        Debug("O ");
        Files.ReadInt(R, fixorgP); Files.ReadInt(R, fixorgD); Files.ReadInt(R, fixorgT);
        Debug("B ");
        Files.ReadInt(R, w); body := SYSTEM.VAL(Command, mod.code + w);
        Files.Read(R, ch);
        IF ch # "O" THEN (*corrupted file*)  mod := NIL; error(4, name); Debug(" Corrupted file for "); Debug(name); OUCH(10) END
      END ;
      IF res = 0 THEN (*fixup of BL*)
        Debug("fixP ");
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
        Debug("fixD ");
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
        Debug("fixT ");
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
        Debug("init ");
        body;   (*initialize module*)
        Debug("done");
      ELSIF res >= 3 THEN importing := name;
        WHILE nofimps > 0 DO DEC(nofimps); DEC(import[nofimps].refcnt) END
      END; 
    END ;
    newmod :=  mod
  END Load;

  (* begin-procedure-description 
---
**ThisCommand** finds and executes a parameterless procedure of module `mod` identified by the string `name`.
  end-procedure-description *)
  PROCEDURE ThisCommand*(mod: Module; name: ARRAY OF CHAR): Command;
    VAR k, adr, fsz, w: INTEGER; ch: CHAR;
      s: ARRAY 32 OF CHAR;
  BEGIN res := 5; w := 0;
    IF mod # NIL THEN
      adr := mod.cmd; SYSTEM.GET(adr, ch);
      WHILE (ch # 0X) & (res # 0) DO k := 0; (*read command name*)
        REPEAT s[k] := ch; INC(k); INC(adr); SYSTEM.GET(adr, ch) UNTIL ch = 0X;
        s[k] := 0X;
        REPEAT INC(adr) UNTIL adr MOD 4 = 0;
        SYSTEM.GET(adr, k); INC(adr, 4);
(*      SYSTEM.GET(adr, fsz); INC(adr, 4); *)
        IF (s = name) & (k MOD 4 = 0) THEN res := 0; w := mod.code + k ELSE SYSTEM.GET(adr, ch) END
      END
    END
    RETURN SYSTEM.VAL(Command, w)
  END ThisCommand;

  (* begin-procedure-description 
---
**Free** recursively removes modules imported by a module and the module itself from memory if no other loaded modules import it, or returns an error.
  end-procedure-description *)
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

  (* begin-procedure-description 
---
**Init** calls `Files.Init`, sets the module table start and allocation pointer and module root and limit and makes room for the stack by decreasing the limit.
  end-procedure-description *)
  PROCEDURE Init*;
  BEGIN Files.Init; MTOrg := SYSTEM.REG(MT);
    SYSTEM.GET(16, AllocPtr); SYSTEM.GET(20, root); SYSTEM.GET(24, limit); DEC(limit, 8000H)
  END Init;

  (* begin-procedure-description
---
**The initialzation code for this module** calls `Init` and then dynamically loads the `Oberon` module and its imports. `Oberon` is not expected to return.
  end-procedure-description *)
BEGIN  OUCH(77);  OUCH(79);  OUCH(68);  OUCH(85);  OUCH(76);  OUCH(69);  OUCH(83);  OUCH(10);
    Init; Load("Oberon", M);
    LED(res); REPEAT UNTIL FALSE  (*only if load fails*)
END Modules.
