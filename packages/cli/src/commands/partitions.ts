import type { Command } from "commander";
import { partitionErrorMessage, validatePartition } from "@unlikeotherai/kelpie-shared";
import { deviceCommand } from "./helpers.js";
import { printValidationError } from "./partition-options.js";

/**
 * Storage-partition lifecycle commands.
 *
 * A partition is created implicitly by `kelpie tab new --partition <id>`;
 * these commands list what exists and tear one down. Deletion is idempotent —
 * an unknown id reports `existed: false` rather than failing.
 */
export function registerPartitions(program: Command): void {
  program
    .command("partitions")
    .description("List storage partitions and how many tabs each holds")
    .action(async () => {
      await deviceCommand(program, "getPartitions");
    });

  const partition = program
    .command("partition")
    .description("Manage storage partitions");

  partition
    .command("delete <id>")
    .description("Delete a storage partition, closing every tab bound to it")
    .action(async (id: string) => {
      const result = validatePartition(id);
      if (!result.ok) {
        printValidationError(program, `invalid partition id: ${partitionErrorMessage(result.reason)}`);
        return;
      }
      await deviceCommand(program, "deletePartition", { id });
    });
}
