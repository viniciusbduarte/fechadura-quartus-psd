package projeto_types;
    typedef struct packed {
        logic [3:0] BCD5;
        logic [3:0] BCD4;
        logic [3:0] BCD3;
        logic [3:0] BCD2;
        logic [3:0] BCD1;
        logic [3:0] BCD0;
    } bcdPac_t;

    typedef struct packed {
        logic [11:0][3:0] digits;
    } senhaPac_t;
	 
	typedef struct packed {
        logic [19:0][3:0] digits;
    } digitosPac_t;


    typedef struct packed {
        logic        bip_status;
        logic [5:0]  bip_time;
        logic [5:0]  tranca_aut_time;
        senhaPac_t   senha_master;
        senhaPac_t   senha_1;
        senhaPac_t   senha_2;
        senhaPac_t   senha_3;
        senhaPac_t   senha_4;
    } setupPac_t;
endpackage