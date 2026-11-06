# Security Policy / Política de Segurança — Ryoku OS

## Idiomas / Languages

Português e inglês. Reportes aceitos em qualquer um dos dois.

---

## Versões suportadas / Supported versions

O projeto está em **fundação**. Ainda **não** há releases públicas de ISO, instalador ou pacotes “suportados”.

| Componente | Estado | Notas |
|------------|--------|-------|
| Documentação / estrutura do repo | Ativo | Correções via issue/PR |
| Zaquion Core | Ainda sem código de produção | Sem SLA |
| Kernel Linux | Upstream (não vendorado aqui) | Seguir processo do kernel.org / distro de referência |
| ISO / instalador | Não existente | N/A |

Quando houver releases, esta tabela será atualizada com versões e janelas de suporte.

---

## Como reportar uma vulnerabilidade / How to report a vulnerability

**Não** abra issue pública para falhas de segurança exploráveis.

1. Prefira o canal privado do GitHub **Security Advisories** (quando o repositório público existir e estiver habilitado).
2. Se o advisory ainda não estiver disponível, use o contato de segurança que for publicado no perfil da organização GitHub do Ryoku OS (a definir na publicação).
3. Inclua, quando possível:
   - Descrição do impacto
   - Passos de reprodução (sem exploit completo se for destrutivo; PoC mínimo)
   - Versão / commit / ambiente (QEMU, bare metal, etc.)
   - Se a falha está no kernel upstream, em Zaquion Core, no instalador, ou na documentação

Resposta esperada (meta, não garantia nesta fase): confirmação em até alguns dias úteis após o canal público existir.

---

## Escopo / Scope

**No escopo (quando o software existir):**

- Serviços e ferramentas Zaquion Core
- Scripts de packaging/instalador deste repositório
- Harness de testes que puder expor credenciais ou execução remota insegura

**Fora de escopo / Out of scope:**

- Vulnerabilidades apenas no Linux upstream sem envolvimento de patches Ryoku — reporte também (ou preferencialmente) via processo do kernel
- Ryoku Desktop enquanto permanecer repositório externo (use a política daquele projeto)
- Engenharia social, spam, DoS em infraestrutura de terceiros
- Relatos sem detalhe reproduzível

---

## Regras para contribuidores / Contributor rules

- Nunca commit de segredos, chaves, tokens ou dados pessoais
- Não adicione backdoors, telemetria oculta ou atualizações forçadas sem transparência
- Dependências de terceiros: registrar licença e origem; preferir versões com manutenção ativa
- Em discussões públicas, não publique exploits prontos para abuso

---

## Aviso legal / Disclaimer

Este software (quando existir) será fornecido “como está”, sem garantia, até que uma política de suporte formal seja publicada. A fundação documental **não** constitui produto de segurança avaliado.
