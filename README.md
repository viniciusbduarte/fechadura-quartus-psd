# Fechadura Eletrônica em Quartus

Projeto de FPGA para uma fechadura eletrônica desenvolvida para a placa DE1-SoC no Quartus Prime. O código principal está em SystemVerilog e o restante dos arquivos do projeto é usado pelo Quartus para compilar, simular e gerar os relatórios da síntese.

## Arquivos principais

- `DE1_SOC_golden_top.sv`: módulo top-level do projeto. Faz a ligação entre o teclado matricial, os botões, os switches, os displays de 7 segmentos e os módulos internos.
- `setup.sv`: máquina de estados responsável pelo menu de configuração, cadastro de senhas e ajuste de tempos da fechadura.
- `decodificador_teclado.sv`: lê o teclado matricial, aplica debounce/timeout e converte as teclas pressionadas para a estrutura de dígitos usada pelo sistema.
- `projeto_types.sv`: pacote com os tipos compartilhados entre os módulos, como as estruturas de senha, BCD e configuração.
- `segment7.sv`: decodificador de valores BCD para os segmentos do display de 7 segmentos.
- `debounce.sv`: filtro simples para reduzir ruído mecânico em entradas digitais.
- `divfreq.sv`: divisor de frequência usado para gerar o clock de 1 kHz a partir do clock de 50 MHz.
- `filelist.txt`: lista auxiliar de arquivos de fonte usada pelo fluxo do projeto.

## Arquivos de projeto do Quartus

- `fechadura-eletronica.qpf`: arquivo principal do projeto Quartus.
- `fechadura-eletronica.qsf`: arquivo de configurações e atribuições de pinos do projeto.
- `fechadura-eletronica.qws`: arquivo da sessão do Quartus.
- `fechadura-eletronica_assignment_defaults.qdf`: valores padrão de atribuições usados pelo Quartus.

## Pastas geradas

- `db/`: banco de dados interno de compilação do Quartus.
- `incremental_db/`: dados de compilação incremental.
- `output_files/`: arquivos finais gerados na compilação, como relatórios e bitstreams.

## Observações

- Os arquivos dentro de `db/`, `incremental_db/` e `output_files/` são gerados automaticamente pelo Quartus e não precisam ser editados manualmente.
- O projeto foi configurado para a família Cyclone V, usada na DE1-SoC.